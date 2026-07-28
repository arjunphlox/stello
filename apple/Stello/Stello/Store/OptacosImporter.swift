import Foundation
import SwiftData

// MARK: - OptacosImporter

enum OptacosImporter {
    static let importedFlagKey = "optacos.imported.v2"
    private static let legacyImportedFlagKey = "optacos.imported.v1"
    nonisolated static let placeholderImageID = "3J1aDWLqoCZI38iuKXlxAHyrlFA"
    private nonisolated static let imageConcurrency = 5
    private nonisolated static let spreadWeekCount = 24

    /// Ordered so import is deterministic; a cross-collection slug collision is disambiguated
    /// in favor of the earlier collection (Typefaces > Websites > Creatives > …).
    /// Geographies (places) are excluded — place cards are not imported.
    private static let entityCollections: [(name: String, kind: ItemKind)] = [
        ("Typefaces", .typeface),
        ("Websites", .website),
        ("Creatives", .individual),
        ("Agency/ Studio", .studio),
        ("Type Foundries", .foundry),
    ]

    private static let refFieldKinds: [String: ItemKind] = [
        "Type Foundry": .foundry,
        "Type Designer": .individual,
        "Founders / Designers": .individual,
        "Founder(s) / Company": .individual,
        "Creatives": .individual,
        "Team": .individual,
        "Typography": .typeface,
        "Typefaces": .typeface,
        "Websites": .website,
        "Work": .website,
        "Agency Studio": .studio,
        "Site Designer / Agency / Studio": .studio,
        "Branding Made By": .studio,
        "Geography": .place,
        "Location & Region": .place,
        "Website": .website,
        "Family Font Names": .typeface,
        "Distributed On": .foundry,
        "Type Foundries": .foundry,
    ]

    // MARK: - Public entry

    /// Import tuning — tests disable the once-guard and network fetch for determinism.
    nonisolated struct Options: Sendable {
        var fetchImages: Bool = true
        var respectGuard: Bool = true

        /// Offline, guard-free run for unit tests.
        nonisolated static let offline = Options(fetchImages: false, respectGuard: false)
    }

    /// Runs once after demo seed; idempotent by slug and guarded by UserDefaults + existing typed items.
    static func importIfNeeded(in context: ModelContext, options: Options = Options()) async {
        await migrateOptacosDatesIfNeeded(in: context)

        if options.respectGuard {
            if UserDefaults.standard.bool(forKey: importedFlagKey) { return }
            if hasTypedItems(in: context) {
                UserDefaults.standard.set(true, forKey: importedFlagKey)
                return
            }
        }

        guard let root = await Task.detached(priority: .utility, operation: { loadSeedRoot() }).value else {
            print("⚠️ OptacosImporter: OptacosSeed.json not found or invalid")
            return
        }

        let collections = root["collections"] as? [String: [String: Any]] ?? [:]
        var slugKindMap = buildSlugKindMap(collections: collections)
        let tagCatalog = buildTagCatalog(collections: collections)

        var importedCount = 0
        var pendingImages: [PendingImage] = []
        var usedSlugs = Set<String>()
        var importQueue: [(row: [String: Any], slug: String, kind: ItemKind, collectionName: String)] = []

        for (collectionName, kind) in entityCollections {
            guard let col = collections[collectionName],
                  let items = col["items"] as? [[String: Any]] else { continue }

            for row in items {
                guard let slug = row["slug"] as? String, !slug.isEmpty else { continue }
                slugKindMap[slug] = kind

                var itemSlug = slug
                if usedSlugs.contains(slug) {
                    itemSlug = "\(slug)-\(kind.rawValue)"
                } else {
                    let exists = await MainActor.run { itemExists(slug: slug, in: context) }
                    if exists { continue }
                }
                usedSlugs.insert(itemSlug)
                importQueue.append((row, itemSlug, kind, collectionName))
            }
        }

        let spreadTotal = importQueue.count
        for (spreadIndex, entry) in importQueue.enumerated() {
            let result = await buildItem(
                row: entry.row,
                slug: entry.slug,
                kind: entry.kind,
                collectionName: entry.collectionName,
                slugKindMap: slugKindMap,
                tagCatalog: tagCatalog
            )
            result.item.addedAt = addedAt(forSpreadIndex: spreadIndex, total: spreadTotal)

            await MainActor.run {
                context.insert(result.item)
                for tag in result.tags {
                    context.insert(tag)
                    tag.item = result.item
                }
                for img in result.images {
                    context.insert(img)
                    img.item = result.item
                }
                try? context.save()
            }

            pendingImages.append(contentsOf: result.pendingDownloads)
            importedCount += 1
        }

        await applyTagCollections(
            collections: collections,
            context: context,
            slugKindMap: slugKindMap
        )

        if options.fetchImages {
            await downloadAndAttachImages(pendingImages, context: context)
        }

        await MainActor.run {
            try? context.save()
            if options.respectGuard {
                UserDefaults.standard.set(true, forKey: importedFlagKey)
            }
        }

        print("✅ OptacosImporter: imported \(importedCount) items, fetched images for \(options.fetchImages ? pendingImages.count : 0) slots")
    }

    // MARK: - v1 → v2 migration

    /// One-time upgrade for installs that ran the v1 import: drop place cards and re-spread `addedAt`.
    private static func migrateOptacosDatesIfNeeded(in context: ModelContext) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: importedFlagKey) else { return }
        guard defaults.bool(forKey: legacyImportedFlagKey) else { return }

        await MainActor.run {
            deletePlaceItems(in: context)
        }

        guard let root = await Task.detached(priority: .utility, operation: { loadSeedRoot() }).value else {
            defaults.set(true, forKey: importedFlagKey)
            return
        }

        let collections = root["collections"] as? [String: [String: Any]] ?? [:]
        // Fetch + re-date in one MainActor block — Item is a PersistentModel and must not cross actors.
        let total = await MainActor.run { () -> Int in
            let itemsToSpread = fetchItemsForDateMigration(in: context, collections: collections)
            for (index, item) in itemsToSpread.enumerated() {
                item.addedAt = addedAt(forSpreadIndex: index, total: itemsToSpread.count)
            }
            try? context.save()
            defaults.set(true, forKey: importedFlagKey)
            return itemsToSpread.count
        }

        print("✅ OptacosImporter: migrated v1 → v2 (\(total) items re-dated, place cards removed)")
    }

    /// Spread index `i` of `N` items across the last 24 ISO weeks (oldest = 24 weeks ago, newest = this week).
    private static func addedAt(forSpreadIndex index: Int, total: Int) -> Date {
        let weekOffset = spreadWeekCount - 1 - (index * (spreadWeekCount - 1) / max(total - 1, 1))
        return isoWeekAnchor(weeksAgo: weekOffset)
    }

    /// Noon on Monday of the ISO week `weeksAgo` before the current ISO week.
    private static func isoWeekAnchor(weeksAgo: Int) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let now = Date.now
        guard let thisWeekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) else { return now }
        guard let targetWeekStart = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeekStart) else {
            return now
        }
        return cal.date(byAdding: .hour, value: 12, to: targetWeekStart) ?? targetWeekStart
    }

    @MainActor
    private static func deletePlaceItems(in context: ModelContext) {
        let placeKind = ItemKind.place.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.kind == placeKind })
        guard let places = try? context.fetch(descriptor) else { return }
        for item in places {
            context.delete(item)
        }
        try? context.save()
    }

    /// Non-link typed items excluding demo seeds, ordered like the import loop then by slug.
    @MainActor
    private static func fetchItemsForDateMigration(
        in context: ModelContext,
        collections: [String: [String: Any]]
    ) -> [Item] {
        let demoSlugs = SeedData.catalogManagedSlugs()
        let linkKind = ItemKind.link.rawValue
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.kind != linkKind })
        let candidates = ((try? context.fetch(descriptor)) ?? []).filter { !demoSlugs.contains($0.slug) }

        var ordered: [Item] = []
        var seen = Set<String>()

        for (collectionName, kind) in entityCollections {
            guard let rows = collections[collectionName]?["items"] as? [[String: Any]] else { continue }
            for row in rows {
                guard let slug = row["slug"] as? String else { continue }
                let slugs = [slug, "\(slug)-\(kind.rawValue)"]
                guard let item = candidates.first(where: { slugs.contains($0.slug) && !seen.contains($0.slug) }) else {
                    continue
                }
                ordered.append(item)
                seen.insert(item.slug)
            }
        }

        let remainder = candidates
            .filter { !seen.contains($0.slug) }
            .sorted { $0.slug < $1.slug }
        ordered.append(contentsOf: remainder)
        return ordered
    }

    // MARK: - Guards

    private static func hasTypedItems(in context: ModelContext) -> Bool {
        let linkKind = ItemKind.link.rawValue
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { $0.kind != linkKind }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    @MainActor
    private static func itemExists(slug: String, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.slug == slug })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    // MARK: - Seed loading

    nonisolated private static func loadSeedRoot() -> [String: Any]? {
        for bundle in Bundle.allBundles {
            guard let url = bundle.url(forResource: "OptacosSeed", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            return root
        }
        return nil
    }

    static func seedCollectionCounts(from bundle: Bundle? = nil) -> (typefaces: Int, websites: Int, creatives: Int)? {
        let bundles = bundle.map { [$0] } ?? Bundle.allBundles
        for bundle in bundles {
            guard let url = bundle.url(forResource: "OptacosSeed", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let collections = root["collections"] as? [String: [String: Any]] else { continue }
            func count(_ name: String) -> Int {
                (collections[name]?["items"] as? [[String: Any]])?.count ?? 0
            }
            return (count("Typefaces"), count("Websites"), count("Creatives"))
        }
        return nil
    }

    // MARK: - Slug / tag catalogs

    private static func buildSlugKindMap(collections: [String: [String: Any]]) -> [String: ItemKind] {
        var map: [String: ItemKind] = [:]
        for (name, kind) in entityCollections {
            guard let items = collections[name]?["items"] as? [[String: Any]] else { continue }
            for row in items {
                if let slug = row["slug"] as? String { map[slug] = kind }
            }
        }
        return map
    }

    private struct TagEntry: Sendable {
        var title: String
        var facet: String
    }

    private static func buildTagCatalog(collections: [String: [String: Any]]) -> [String: TagEntry] {
        var catalog: [String: TagEntry] = [:]
        let tagCollections = [
            "Website Tags", "Typeface Tags", "Creative Tags", "Type Foundry Tags",
        ]
        for name in tagCollections {
            guard let items = collections[name]?["items"] as? [[String: Any]] else { continue }
            for row in items {
                guard let slug = row["slug"] as? String else { continue }
                let title = (row["Title"] as? String) ?? slug
                let facet = (row["Tag Filter"] as? String)
                    ?? (row["Tags Filter"] as? String)
                    ?? name
                catalog[slug] = TagEntry(title: title, facet: facet)
            }
        }
        return catalog
    }

    // MARK: - Item construction

    private struct BuildResult {
        var item: Item
        var tags: [Tag]
        var images: [ItemImage]
        var pendingDownloads: [PendingImage]
    }

    private struct PendingImage: Sendable {
        var slug: String
        var url: URL
        var role: String
        var label: String?
        var isPrimary: Bool
    }

    private static func buildItem(
        row: [String: Any],
        slug: String,
        kind: ItemKind,
        collectionName: String,
        slugKindMap: [String: ItemKind],
        tagCatalog: [String: TagEntry]
    ) async -> BuildResult {
        let title = titleForRow(row, collectionName: collectionName)
        let urlString = linkValue(row["URL"]) ?? stringValue(row["URL"])
        let domain: String? = urlString.flatMap { URL(string: $0) }.flatMap { CaptureService.domain(from: $0) }
        let summary = stringValue(row["Overview"]) ?? stringValue(row["Description"]) ?? stringValue(row["Bio"]) ?? stringValue(row["Tagline / One-liner"])

        let item = Item(
            slug: slug,
            title: title,
            sourceURL: urlString,
            domain: domain,
            summary: summary,
            needsReview: false,
            enrichmentStatus: "candidates_done",
            kind: kind.rawValue
        )

        var tags: [Tag] = []
        var images: [ItemImage] = []
        var pending: [PendingImage] = []

        switch kind {
        case .typeface:
            let meta = buildTypefaceMeta(row: row, slugKindMap: slugKindMap, tagCatalog: tagCatalog)
            item.setMetadata(meta)
            appendTypefaceTags(from: row, tagCatalog: tagCatalog, into: &tags)
            pending = collectTypefaceImages(row: row, slug: slug, images: &images)
        case .website:
            item.setMetadata(buildWebsiteMeta(row: row, slugKindMap: slugKindMap, tagCatalog: tagCatalog))
            pending = collectWebsiteImages(row: row, slug: slug, images: &images)
        case .individual:
            item.setMetadata(buildIndividualMeta(row: row, slugKindMap: slugKindMap))
        case .studio:
            item.setMetadata(buildStudioMeta(row: row, slugKindMap: slugKindMap))
        case .foundry:
            item.setMetadata(buildFoundryMeta(row: row, slugKindMap: slugKindMap, tagCatalog: tagCatalog))
            appendFoundryTags(from: row, tagCatalog: tagCatalog, into: &tags)
        case .place:
            item.setMetadata(buildPlaceMeta(row: row))
        case .music:
            break
        case .link:
            break
        }

        return BuildResult(item: item, tags: tags, images: images, pendingDownloads: pending)
    }

    private static func titleForRow(_ row: [String: Any], collectionName: String) -> String {
        if collectionName == "Agency/ Studio" {
            return stringValue(row["Agency Name"]) ?? stringValue(row["slug"]) ?? "Untitled"
        }
        return stringValue(row["Name"]) ?? stringValue(row["Title"]) ?? stringValue(row["slug"]) ?? "Untitled"
    }

    // MARK: - Metadata builders

    private static func buildTypefaceMeta(
        row: [String: Any],
        slugKindMap: [String: ItemKind],
        tagCatalog: [String: TagEntry]
    ) -> TypefaceMeta {
        var meta = TypefaceMeta()
        meta.overview = stringValue(row["Overview"])
        meta.description = stringValue(row["Description"])
        meta.specimenURL = stringValue(row["Specimen URL"])
        meta.specimenLink = linkValue(row["Specimen Link"])
        meta.typeDesigner = entityRefs(row["Type Designer"], field: "Type Designer", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.typeDesignerFallback = stringValue(row["Type Designer Fallback"])
        meta.typeFoundry = entityRefs(row["Type Foundry"], field: "Type Foundry", slugKindMap: slugKindMap, tagCatalog: tagCatalog).first
        meta.distributedOn = entityRefs(row["Distributed On"], field: "Distributed On", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.license = stringValue(row["License"])
        meta.paidOrFree = stringValue(row["Paid or Free"])
        meta.trialAvailability = boolValue(row["Trial Availability"])
        meta.studentDiscount = boolValue(row["Student Discount"])
        meta.releaseYear = stringValue(row["Release Year"])
        meta.lastUpdate = stringValue(row["Last Update"])
        meta.version = stringValue(row["Version of the Font"])
        meta.familyCount = stringValue(row["Family Count"])
        meta.familyFontNames = entityRefs(row["Family Font Names"], field: "Family Font Names", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.weightsCount = stringValue(row["Weights Count"])
        meta.weightCount = intValue(row["Weight Count"])
        meta.weightTypes = refSlugsAsStrings(row["Weight Types"], tagCatalog: tagCatalog)
        meta.stylesCount = stringValue(row["Styles Count"])
        meta.styleCount = intValue(row["Style Count"])
        meta.styleTypes = refSlugsAsStrings(row["Style Types"], tagCatalog: tagCatalog)
        meta.languageSupport = intValue(row["Language Support"])
        meta.languagesCount = stringValue(row["Languages Count"])
        meta.languagesRegion = refSlugsAsStrings(row["Languages Region"], tagCatalog: tagCatalog)
        meta.formatsCount = stringValue(row["Formats Count"])
        meta.formatsCount2 = intValue(row["Formats Count 2"])
        meta.availableFormats = refSlugsAsStrings(row["Available Formats"], tagCatalog: tagCatalog)
        meta.startingPrice = stringValue(row["Starting Price"])
        meta.variableFontSupport = boolValue(row["Variable Font Support"])
        meta.openTypeFeatures = refSlugsAsStrings(row["OpenType Features"], tagCatalog: tagCatalog)
        meta.classification = refSlugsAsStrings(row["Classification"], tagCatalog: tagCatalog)
        meta.personality = refSlugsAsStrings(row["Personality"], tagCatalog: tagCatalog)
        meta.highlights = stringValue(row["Highlights"])
        meta.useCase = stringValue(row["Use Case"])
        meta.designFeatures = formattedValue(row["Design Features"])
        meta.pairingFonts = stringValue(row["Pairing Fonts"])
        meta.similarFonts = stringValue(row["Similar Fonts Suggestions"])
        meta.forkFonts = stringValue(row["Fork Fonts"])
        meta.faqs = collectFAQs(from: row)
        meta.creatives = entityRefs(row["Creatives"], field: "Creatives", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.websites = entityRefs(row["Websites"], field: "Websites", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        return meta
    }

    private static func buildWebsiteMeta(
        row: [String: Any],
        slugKindMap: [String: ItemKind],
        tagCatalog: [String: TagEntry]
    ) -> WebsiteMeta {
        var meta = WebsiteMeta()
        meta.tagline = stringValue(row["Tagline / One-liner"])
        meta.description = stringValue(row["Description"])
        meta.categories = refSlugsAsStrings(row["Category(s)"], tagCatalog: tagCatalog)
        meta.traits = refSlugsAsStrings(row["Trait(s)"], tagCatalog: tagCatalog)
        meta.agencyStudio = entityRefs(row["Agency Studio"], field: "Agency Studio", slugKindMap: slugKindMap, tagCatalog: tagCatalog).first
        meta.focusAreas = refSlugsAsStrings(row["Focus Areas"], tagCatalog: tagCatalog)
        meta.versionHistory = formattedValue(row["Version History"])
        meta.contentFormats = refSlugsAsStrings(row["Content Formats"], tagCatalog: tagCatalog)
        meta.review = formattedValue(row["Review"])
        meta.platform = refSlugsAsStrings(row["Platform"], tagCatalog: tagCatalog)
        meta.techStack = refSlugsAsStrings(row["Tech Stack"], tagCatalog: tagCatalog)
        meta.founders = entityRefs(row["Founder(s) / Company"], field: "Founder(s) / Company", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.founderName = stringValue(row["Founder Name"])
        meta.brandingMadeBy = entityRefs(row["Branding Made By"], field: "Branding Made By", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.siteDesignerAgency = entityRefs(row["Site Designer / Agency / Studio"], field: "Site Designer / Agency / Studio", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.agencyName = stringValue(row["Agency Name"])
        meta.agencyURL = stringValue(row["Agency URL"])
        meta.creatives = entityRefs(row["Creatives"], field: "Creatives", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.contactDetails = stringValue(row["Contact Details"])
        meta.socialLinks = stringValue(row["Social Links / Community Channels"])
        meta.typography = entityRefs(row["Typography"], field: "Typography", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.typefaceCount = stringValue(row["Typeface Count"])
        meta.typeFoundries = entityRefs(row["Type Foundries"], field: "Type Foundries", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.webPages = refSlugsAsStrings(row["Web Pages"], tagCatalog: tagCatalog)
        meta.webPagesCount = stringValue(row["Web Pages Count"])
        meta.keyComponents = refSlugsAsStrings(row["Key Components"], tagCatalog: tagCatalog)
        meta.keyComponentsCount = stringValue(row["Key Components Count"])
        meta.firstPublished = stringValue(row["First Published"])
        meta.dateAdded = dateValue(row["Date Added"])
        meta.dateUpdated = dateValue(row["Date Updated"])
        return meta
    }

    private static func buildIndividualMeta(row: [String: Any], slugKindMap: [String: ItemKind]) -> IndividualMeta {
        var meta = IndividualMeta()
        meta.pronouns = stringValue(row["Pronouns"])
        meta.bio = stringValue(row["Bio"])
        meta.location = entityRefs(row["Location & Region"], field: "Location & Region", slugKindMap: slugKindMap, tagCatalog: [:]).first
        meta.institutions = stringValue(row["Institutions"])
        meta.website = entityRefs(row["Website"], field: "Website", slugKindMap: slugKindMap, tagCatalog: [:]).first
        meta.fallbackWebsite = linkValue(row["Fallback Website"])
        meta.ownWebsite = stringValue(row["Own Website"])
        meta.professions = refSlugsAsStrings(row["Professions"], tagCatalog: [:])
        meta.traits = refSlugsAsStrings(row["Traits"], tagCatalog: [:])
        meta.professionalExperience = intValue(row["Professional Experience"])
        meta.currentRole = stringValue(row["Current Role"])
        meta.currentEmployer = stringValue(row["Current Employer / Project"])
        meta.notableWorks = formattedValue(row["Notable Works"])
        meta.signatureStyle = formattedValue(row["Signature Style"])
        meta.ownProductsList = stringValue(row["Own Products List"])
        meta.speaking = stringValue(row["Speaking"])
        meta.workshops = stringValue(row["Workshops"])
        meta.communityWork = stringValue(row["Community Work"])
        meta.toolsAndTechStack = stringValue(row["Tools & Tech Stack"])
        meta.email = stringValue(row["Email"])
        meta.xURL = linkValue(row["X"]) ?? stringValue(row["X (Plain text old)"])
        meta.instagramURL = linkValue(row["Instagram"]) ?? stringValue(row["Instagram old"])
        meta.linkedInURL = linkValue(row["LinkedIn"]) ?? stringValue(row["Linkedin old"])
        meta.behanceURL = linkValue(row["Behance"]) ?? stringValue(row["Behance old"])
        meta.bluesky = stringValue(row["Bluesky"])
        meta.mastodon = stringValue(row["Mastodon"])
        meta.threads = stringValue(row["Threads"])
        meta.blogLink = linkValue(row["Blog Link"])
        meta.shopLink = linkValue(row["Shop / Merch"])
        meta.favouriteBook = stringValue(row["Favourite Book"])
        meta.funFact = formattedValue(row["Fun Fact"])
        meta.hobbies = formattedValue(row["Hobbies / Interests"])
        meta.typefaces = entityRefs(row["Typefaces"], field: "Typefaces", slugKindMap: slugKindMap, tagCatalog: [:])
        meta.typeFoundries = entityRefs(row["Type Foundries"], field: "Type Foundries", slugKindMap: slugKindMap, tagCatalog: [:])
        return meta
    }

    private static func buildStudioMeta(row: [String: Any], slugKindMap: [String: ItemKind]) -> StudioMeta {
        StudioMeta(
            work: entityRefs(row["Work"], field: "Work", slugKindMap: slugKindMap, tagCatalog: [:]),
            team: entityRefs(row["Team"], field: "Team", slugKindMap: slugKindMap, tagCatalog: [:])
        )
    }

    private static func buildFoundryMeta(
        row: [String: Any],
        slugKindMap: [String: ItemKind],
        tagCatalog: [String: TagEntry]
    ) -> FoundryMeta {
        var meta = FoundryMeta()
        meta.description = stringValue(row["Description"])
        meta.category = stringValue(row["Category"])
        meta.geography = entityRefs(row["Geography"], field: "Geography", slugKindMap: slugKindMap, tagCatalog: tagCatalog).first
        meta.foundedYear = stringValue(row["Founded Year"])
        meta.foundersDesigners = entityRefs(row["Founders / Designers"], field: "Founders / Designers", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.priceRange = stringValue(row["Price Range"])
        meta.trialFonts = boolValue(row["Availability of Trial Fonts"])
        meta.studentDiscount = boolValue(row["Student Discount?"])
        meta.licensingTypes = refSlugsAsStrings(row["Licensing Types"], tagCatalog: tagCatalog)
        meta.designPhilosophy = stringValue(row["Design Philosophy and Intent"])
        meta.popularFonts = refSlugsAsStrings(row["Popular Fonts or Styles"], tagCatalog: tagCatalog)
        meta.specialisation = refSlugsAsStrings(row["Specialisation"], tagCatalog: tagCatalog)
        meta.customServices = refSlugsAsStrings(row["Custom Services"], tagCatalog: tagCatalog)
        meta.social = stringValue(row["Social"])
        meta.email = stringValue(row["Email"])
        meta.thoughts = formattedValue(row["Thoughts"])
        meta.distribution = refSlugsAsStrings(row["Distribution"], tagCatalog: tagCatalog)
        meta.typefaces = entityRefs(row["Typefaces"], field: "Typefaces", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.websites = entityRefs(row["Websites"], field: "Websites", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        meta.creatives = entityRefs(row["Creatives"], field: "Creatives", slugKindMap: slugKindMap, tagCatalog: tagCatalog)
        return meta
    }

    private static func buildPlaceMeta(row: [String: Any]) -> PlaceMeta {
        PlaceMeta(city: stringValue(row["City"]), country: stringValue(row["Country"]))
    }

    // MARK: - Tags on entities

    private static func appendTypefaceTags(
        from row: [String: Any],
        tagCatalog: [String: TagEntry],
        into tags: inout [Tag]
    ) {
        addTags(fromRefField: row["Classification"], facet: "Classification", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Personality"], facet: "Personality", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Weight Types"], facet: "Weight Types", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Style Types"], facet: "Style Types", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Languages Region"], facet: "Languages Region", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Available Formats"], facet: "Available Formats", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Website Tags (All)"], facet: "Website Tags", tagCatalog: tagCatalog, into: &tags)
    }

    private static func appendFoundryTags(
        from row: [String: Any],
        tagCatalog: [String: TagEntry],
        into tags: inout [Tag]
    ) {
        addTags(fromRefField: row["Licensing Types"], facet: "Licensing Types", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Specialisation"], facet: "Specialisation", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Custom Services"], facet: "Custom Services", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Distribution"], facet: "Distribution Platform", tagCatalog: tagCatalog, into: &tags)
        addTags(fromRefField: row["Tags / Filters"], facet: "Tags / Filters", tagCatalog: tagCatalog, into: &tags)
    }

    private static func addTags(
        fromRefField value: Any?,
        facet: String,
        tagCatalog: [String: TagEntry],
        into tags: inout [Tag]
    ) {
        for slug in refSlugs(value) {
            let name = tagCatalog[slug]?.title ?? slug.replacingOccurrences(of: "-", with: " ")
            let category = tagCatalog[slug]?.facet ?? facet
            tags.append(Tag(name: name, category: category, weight: 0.75, source: "rule"))
        }
    }

    // MARK: - Tag collection pass

    private static func applyTagCollections(
        collections: [String: [String: Any]],
        context: ModelContext,
        slugKindMap: [String: ItemKind]
    ) async {
        struct TagAssignment: Sendable {
            var targetSlug: String
            var tagName: String
            var facet: String
        }

        var assignments: [TagAssignment] = []

        let mappings: [(tagCollection: String, targetField: String, defaultFacet: String)] = [
            ("Website Tags", "Websites", "Focus Area"),
            ("Typeface Tags", "Typefaces", "Family Name"),
            ("Creative Tags", "Creatives", "Profession"),
        ]

        for mapping in mappings {
            guard let items = collections[mapping.tagCollection]?["items"] as? [[String: Any]] else { continue }
            for row in items {
                guard let tagSlug = row["slug"] as? String else { continue }
                let tagName = stringValue(row["Title"]) ?? tagSlug
                let facet = stringValue(row["Tag Filter"])
                    ?? stringValue(row["Tags Filter"])
                    ?? mapping.defaultFacet
                guard let refField = row[mapping.targetField] else { continue }
                for targetSlug in refSlugs(refField) {
                    assignments.append(TagAssignment(targetSlug: targetSlug, tagName: tagName, facet: facet))
                }
            }
        }

        await MainActor.run {
            for assignment in assignments {
                guard let item = fetchItem(slug: assignment.targetSlug, in: context) else { continue }
                if item.tags?.contains(where: { $0.name == assignment.tagName && $0.category == assignment.facet }) == true {
                    continue
                }
                let tag = Tag(name: assignment.tagName, category: assignment.facet, weight: 0.8, source: "rule")
                context.insert(tag)
                tag.item = item
            }
            try? context.save()
        }

        _ = slugKindMap // reserved for future cross-tag resolution
    }

    @MainActor
    private static func fetchItem(slug: String, in context: ModelContext) -> Item? {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.slug == slug })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Images

    private static func collectTypefaceImages(row: [String: Any], slug: String, images: inout [ItemImage]) -> [PendingImage] {
        var pending: [PendingImage] = []
        let specimenFields = [
            "Intro 200", "Intro 120", "Intro 56", "Intro 12", "Intro P",
            "Words - 1", "Words - 2", "Words - 3", "Words - 4", "Words - 5",
            "Sentences - 1", "Sentences - 2", "Sentences - 3",
            "Title Large (200)", "Title Medium (120)", "Title Small (56)",
        ]
        let graphicFields = [
            "Spacing, Strokes", "Rare Letterforms", "Weight & Balance", "Frequent Letters",
            "Long Length", "Pangram", "Balanced Capitals", "Ascenders, Descenders",
        ]

        var coverQueued = false
        for field in specimenFields {
            if let url = imageURL(from: row[field]) {
                let isCover = !coverQueued && field == "Title Large (200)"
                if isCover { coverQueued = true }
                pending.append(PendingImage(
                    slug: slug, url: url, role: ItemImageRole.specimen.rawValue,
                    label: field, isPrimary: isCover
                ))
            }
        }
        if !coverQueued, let firstSpecimen = pending.first {
            pending[0] = PendingImage(
                slug: firstSpecimen.slug, url: firstSpecimen.url,
                role: ItemImageRole.cover.rawValue, label: firstSpecimen.label, isPrimary: true
            )
        } else if coverQueued, let idx = pending.firstIndex(where: { $0.label == "Title Large (200)" }) {
            let p = pending[idx]
            pending[idx] = PendingImage(slug: p.slug, url: p.url, role: ItemImageRole.cover.rawValue, label: p.label, isPrimary: true)
        }

        for field in graphicFields {
            if let url = imageURL(from: row[field]) {
                pending.append(PendingImage(slug: slug, url: url, role: ItemImageRole.graphic.rawValue, label: field, isPrimary: false))
            }
        }
        for (index, url) in imageArrayURLs(from: row["Preview"]).enumerated() {
            pending.append(PendingImage(slug: slug, url: url, role: ItemImageRole.preview.rawValue, label: "Preview \(index + 1)", isPrimary: false))
        }

        for p in pending {
            let img = ItemImage(source: "optacos", isPrimary: p.isPrimary, label: p.label, role: p.role)
            images.append(img)
        }
        return pending
    }

    private static func collectWebsiteImages(row: [String: Any], slug: String, images: inout [ItemImage]) -> [PendingImage] {
        var pending: [PendingImage] = []
        if let url = imageURL(from: row["Cover"]) {
            pending.append(PendingImage(slug: slug, url: url, role: ItemImageRole.cover.rawValue, label: "Cover", isPrimary: true))
        }
        for field in ["Image 1", "Image 2", "Image 3", "Image 4"] {
            if let url = imageURL(from: row[field]) {
                pending.append(PendingImage(slug: slug, url: url, role: ItemImageRole.gallery.rawValue, label: field, isPrimary: false))
            }
        }
        for (index, url) in imageArrayURLs(from: row["Gallery"]).enumerated() {
            pending.append(PendingImage(slug: slug, url: url, role: ItemImageRole.gallery.rawValue, label: "Gallery \(index + 1)", isPrimary: false))
        }
        for (index, url) in imageArrayURLs(from: row["Gallery 2"]).enumerated() {
            pending.append(PendingImage(slug: slug, url: url, role: ItemImageRole.gallery.rawValue, label: "Gallery 2 \(index + 1)", isPrimary: false))
        }
        if pending.isEmpty == false && !pending.contains(where: \.isPrimary),
           let first = pending.first {
            pending[0] = PendingImage(slug: first.slug, url: first.url, role: ItemImageRole.cover.rawValue, label: first.label, isPrimary: true)
        }
        for p in pending {
            images.append(ItemImage(source: "optacos", isPrimary: p.isPrimary, label: p.label, role: p.role))
        }
        return pending
    }

    private static func downloadAndAttachImages(_ pending: [PendingImage], context: ModelContext) async {
        let limiter = ConcurrencyLimiter(limit: imageConcurrency)
        await withTaskGroup(of: (Int, Data?, Int, Int)?.self) { group in
            for (index, item) in pending.enumerated() {
                group.addTask {
                    await limiter.withLimit {
                        guard !item.url.absoluteString.contains(placeholderImageID),
                              let result = await downloadOptacosImage(url: item.url) else {
                            return (index, nil, 0, 0)
                        }
                        return (index, result.0, result.1, result.2)
                    }
                }
            }
            for await result in group {
                guard let (index, data, w, h) = result, let data, index < pending.count else { continue }
                let pendingItem = pending[index]
                await MainActor.run {
                    guard let item = fetchItem(slug: pendingItem.slug, in: context) else { return }
                    let imgs = item.images ?? []
                    if let img = imgs.first(where: { $0.label == pendingItem.label && $0.role == pendingItem.role }) {
                        img.data = data
                        img.width = w
                        img.height = h
                        img.isPrimary = pendingItem.isPrimary
                    }
                }
            }
        }
        await MainActor.run { try? context.save() }
    }

    /// Optacos specimen SVGs can be small — skip CaptureService's 500-byte OG floor.
    private static func downloadOptacosImage(url: URL) async -> (Data, Int, Int)? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (raw, _) = try? await URLSession.shared.data(for: request), !raw.isEmpty else { return nil }
        let (w, h) = CaptureService.imageDimensions(data: raw)
        return (raw, w, h)
    }

    // MARK: - Value parsing

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func formattedValue(_ value: Any?) -> String? {
        stringValue(value)
    }

    private static func linkValue(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String, let i = Int(s) { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    private static func dateValue(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber {
            let date = Date(timeIntervalSince1970: n.doubleValue / 1000)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withFullDate]
            return fmt.string(from: date)
        }
        return nil
    }

    private static func refSlugs(_ value: Any?) -> [String] {
        guard let dict = value as? [String: Any],
              let refs = dict["refs"] as? [String] else { return [] }
        return refs
    }

    private static func refSlugsAsStrings(_ value: Any?, tagCatalog: [String: TagEntry]) -> [String] {
        refSlugs(value).map { slug in
            tagCatalog[slug]?.title ?? slug.replacingOccurrences(of: "-", with: " ")
        }
    }

    private static func entityRefs(
        _ value: Any?,
        field: String,
        slugKindMap: [String: ItemKind],
        tagCatalog: [String: TagEntry]
    ) -> [EntityRef] {
        let kind = refFieldKinds[field]?.rawValue ?? slugKindMap[refSlugs(value).first ?? ""]?.rawValue ?? ItemKind.link.rawValue
        return refSlugs(value).map { slug in
            EntityRef(
                name: tagCatalog[slug]?.title ?? slug.replacingOccurrences(of: "-", with: " "),
                slug: slug,
                kind: slugKindMap[slug]?.rawValue ?? kind
            )
        }
    }

    private static func imageURL(from value: Any?) -> URL? {
        guard let dict = value as? [String: Any],
              let urlString = dict["url"] as? String,
              !urlString.isEmpty,
              !urlString.contains(placeholderImageID),
              let url = URL(string: urlString) else { return nil }
        return url
    }

    private static func imageArrayURLs(from value: Any?) -> [URL] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { imageURL(from: $0) }
    }

    private static func collectFAQs(from row: [String: Any]) -> [FAQItem] {
        var faqs: [FAQItem] = []
        for index in 1...12 {
            let qKey = "Q \(index)"
            let aKey = "A \(index)"
            guard let question = stringValue(row[qKey]), !question.isEmpty else { continue }
            let answer = formattedValue(row[aKey]) ?? ""
            faqs.append(FAQItem(question: question, answer: answer))
        }
        return faqs
    }
}

// MARK: - Concurrency limiter

private actor ConcurrencyLimiter {
    private let limit: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func withLimit<T: Sendable>(_ operation: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        inFlight += 1
    }

    private func release() {
        inFlight -= 1
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}
