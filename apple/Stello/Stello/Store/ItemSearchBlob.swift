import Foundation

/// Builds a lowercase concatenation of all searchable text for an item.
enum ItemSearchBlob {
    /// Persistent per-item cache keyed by item id, invalidated when `updatedAt` changes.
    /// `build(for:)` is called on the main thread once per filter pass, so a plain
    /// dictionary (no actor) is safe here.
    private static var cache: [UUID: (stamp: Date, blob: String)] = [:]

    static func build(for item: Item) -> String {
        if let cached = cache[item.id], cached.stamp == item.updatedAt {
            return cached.blob
        }

        let blob = buildFresh(for: item)
        cache[item.id] = (stamp: item.updatedAt, blob: blob)
        return blob
    }

    private static func buildFresh(for item: Item) -> String {
        var parts: [String] = []

        parts.append(item.title)
        appendOptional(item.summary, to: &parts)
        appendOptional(item.author, to: &parts)
        appendOptional(item.domain, to: &parts)
        appendOptional(item.bodyMarkdown, to: &parts)
        appendOptional(item.extractedText, to: &parts)

        if let tags = item.tags {
            parts.append(contentsOf: tags.map(\.name))
        }

        if let snippets = item.snippets {
            parts.append(contentsOf: snippets.map(\.text))
        }

        parts.append(contentsOf: EnrichmentService.decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON))
        parts.append(contentsOf: metadataSearchTerms(for: item))

        return parts
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    // MARK: - Metadata

    private static func metadataSearchTerms(for item: Item) -> [String] {
        switch item.kind {
        case ItemKind.typeface.rawValue:
            return item.typefaceMeta()?.searchTerms() ?? []
        case ItemKind.website.rawValue:
            return item.websiteMeta()?.searchTerms() ?? []
        case ItemKind.individual.rawValue:
            return item.individualMeta()?.searchTerms() ?? []
        case ItemKind.studio.rawValue:
            return item.studioMeta()?.searchTerms() ?? []
        case ItemKind.foundry.rawValue:
            return item.foundryMeta()?.searchTerms() ?? []
        case ItemKind.place.rawValue:
            return item.placeMeta()?.searchTerms() ?? []
        default:
            return []
        }
    }

    // MARK: - String collectors

    fileprivate static func appendOptional(_ value: String?, to parts: inout [String]) {
        guard let value, !value.isEmpty else { return }
        parts.append(value)
    }

    fileprivate static func appendStrings(_ strings: [String], to parts: inout [String]) {
        parts.append(contentsOf: strings.filter { !$0.isEmpty })
    }

    fileprivate static func appendEntityRef(_ ref: EntityRef?, to parts: inout [String]) {
        guard let ref else { return }
        appendOptional(ref.name, to: &parts)
        appendOptional(ref.slug, to: &parts)
    }

    fileprivate static func appendEntityRefs(_ refs: [EntityRef], to parts: inout [String]) {
        for ref in refs {
            appendOptional(ref.name, to: &parts)
            appendOptional(ref.slug, to: &parts)
        }
    }

    fileprivate static func appendFAQs(_ faqs: [FAQItem], to parts: inout [String]) {
        for faq in faqs {
            appendOptional(faq.question, to: &parts)
            appendOptional(faq.answer, to: &parts)
        }
    }
}

// MARK: - Per-kind metadata search terms

extension TypefaceMeta {
    func searchTerms() -> [String] {
        var parts: [String] = []
        ItemSearchBlob.appendOptional(overview, to: &parts)
        ItemSearchBlob.appendOptional(description, to: &parts)
        ItemSearchBlob.appendOptional(specimenURL, to: &parts)
        ItemSearchBlob.appendOptional(specimenLink, to: &parts)
        ItemSearchBlob.appendEntityRefs(typeDesigner, to: &parts)
        ItemSearchBlob.appendOptional(typeDesignerFallback, to: &parts)
        ItemSearchBlob.appendEntityRef(typeFoundry, to: &parts)
        ItemSearchBlob.appendEntityRefs(distributedOn, to: &parts)
        ItemSearchBlob.appendOptional(license, to: &parts)
        ItemSearchBlob.appendOptional(paidOrFree, to: &parts)
        ItemSearchBlob.appendOptional(releaseYear, to: &parts)
        ItemSearchBlob.appendOptional(lastUpdate, to: &parts)
        ItemSearchBlob.appendOptional(version, to: &parts)
        ItemSearchBlob.appendOptional(familyCount, to: &parts)
        ItemSearchBlob.appendEntityRefs(familyFontNames, to: &parts)
        ItemSearchBlob.appendOptional(weightsCount, to: &parts)
        ItemSearchBlob.appendStrings(weightTypes, to: &parts)
        ItemSearchBlob.appendOptional(stylesCount, to: &parts)
        ItemSearchBlob.appendStrings(styleTypes, to: &parts)
        ItemSearchBlob.appendOptional(languagesCount, to: &parts)
        ItemSearchBlob.appendStrings(languagesRegion, to: &parts)
        ItemSearchBlob.appendOptional(formatsCount, to: &parts)
        ItemSearchBlob.appendStrings(availableFormats, to: &parts)
        ItemSearchBlob.appendOptional(startingPrice, to: &parts)
        ItemSearchBlob.appendStrings(openTypeFeatures, to: &parts)
        ItemSearchBlob.appendStrings(classification, to: &parts)
        ItemSearchBlob.appendStrings(personality, to: &parts)
        ItemSearchBlob.appendOptional(highlights, to: &parts)
        ItemSearchBlob.appendOptional(useCase, to: &parts)
        ItemSearchBlob.appendOptional(designFeatures, to: &parts)
        ItemSearchBlob.appendOptional(pairingFonts, to: &parts)
        ItemSearchBlob.appendOptional(similarFonts, to: &parts)
        ItemSearchBlob.appendOptional(forkFonts, to: &parts)
        ItemSearchBlob.appendFAQs(faqs, to: &parts)
        ItemSearchBlob.appendEntityRefs(creatives, to: &parts)
        ItemSearchBlob.appendEntityRefs(websites, to: &parts)
        return parts
    }
}

extension WebsiteMeta {
    func searchTerms() -> [String] {
        var parts: [String] = []
        ItemSearchBlob.appendOptional(tagline, to: &parts)
        ItemSearchBlob.appendOptional(description, to: &parts)
        ItemSearchBlob.appendStrings(categories, to: &parts)
        ItemSearchBlob.appendStrings(traits, to: &parts)
        ItemSearchBlob.appendEntityRef(agencyStudio, to: &parts)
        ItemSearchBlob.appendStrings(focusAreas, to: &parts)
        ItemSearchBlob.appendOptional(versionHistory, to: &parts)
        ItemSearchBlob.appendStrings(contentFormats, to: &parts)
        ItemSearchBlob.appendOptional(review, to: &parts)
        ItemSearchBlob.appendStrings(platform, to: &parts)
        ItemSearchBlob.appendStrings(techStack, to: &parts)
        ItemSearchBlob.appendEntityRefs(founders, to: &parts)
        ItemSearchBlob.appendOptional(founderName, to: &parts)
        ItemSearchBlob.appendEntityRefs(brandingMadeBy, to: &parts)
        ItemSearchBlob.appendEntityRefs(siteDesignerAgency, to: &parts)
        ItemSearchBlob.appendOptional(agencyName, to: &parts)
        ItemSearchBlob.appendOptional(agencyURL, to: &parts)
        ItemSearchBlob.appendEntityRefs(creatives, to: &parts)
        ItemSearchBlob.appendOptional(contactDetails, to: &parts)
        ItemSearchBlob.appendOptional(socialLinks, to: &parts)
        ItemSearchBlob.appendEntityRefs(typography, to: &parts)
        ItemSearchBlob.appendOptional(typefaceCount, to: &parts)
        ItemSearchBlob.appendEntityRefs(typeFoundries, to: &parts)
        ItemSearchBlob.appendStrings(webPages, to: &parts)
        ItemSearchBlob.appendOptional(webPagesCount, to: &parts)
        ItemSearchBlob.appendStrings(keyComponents, to: &parts)
        ItemSearchBlob.appendOptional(keyComponentsCount, to: &parts)
        ItemSearchBlob.appendOptional(firstPublished, to: &parts)
        ItemSearchBlob.appendOptional(dateAdded, to: &parts)
        ItemSearchBlob.appendOptional(dateUpdated, to: &parts)
        return parts
    }
}

extension IndividualMeta {
    func searchTerms() -> [String] {
        var parts: [String] = []
        ItemSearchBlob.appendOptional(pronouns, to: &parts)
        ItemSearchBlob.appendOptional(bio, to: &parts)
        ItemSearchBlob.appendEntityRef(location, to: &parts)
        ItemSearchBlob.appendOptional(institutions, to: &parts)
        ItemSearchBlob.appendEntityRef(website, to: &parts)
        ItemSearchBlob.appendOptional(fallbackWebsite, to: &parts)
        ItemSearchBlob.appendOptional(ownWebsite, to: &parts)
        ItemSearchBlob.appendStrings(professions, to: &parts)
        ItemSearchBlob.appendStrings(traits, to: &parts)
        ItemSearchBlob.appendOptional(currentRole, to: &parts)
        ItemSearchBlob.appendOptional(currentEmployer, to: &parts)
        ItemSearchBlob.appendOptional(notableWorks, to: &parts)
        ItemSearchBlob.appendOptional(signatureStyle, to: &parts)
        ItemSearchBlob.appendOptional(ownProductsList, to: &parts)
        ItemSearchBlob.appendOptional(speaking, to: &parts)
        ItemSearchBlob.appendOptional(workshops, to: &parts)
        ItemSearchBlob.appendOptional(communityWork, to: &parts)
        ItemSearchBlob.appendOptional(toolsAndTechStack, to: &parts)
        ItemSearchBlob.appendOptional(email, to: &parts)
        ItemSearchBlob.appendOptional(xURL, to: &parts)
        ItemSearchBlob.appendOptional(instagramURL, to: &parts)
        ItemSearchBlob.appendOptional(linkedInURL, to: &parts)
        ItemSearchBlob.appendOptional(behanceURL, to: &parts)
        ItemSearchBlob.appendOptional(bluesky, to: &parts)
        ItemSearchBlob.appendOptional(mastodon, to: &parts)
        ItemSearchBlob.appendOptional(threads, to: &parts)
        ItemSearchBlob.appendOptional(blogLink, to: &parts)
        ItemSearchBlob.appendOptional(shopLink, to: &parts)
        ItemSearchBlob.appendOptional(favouriteBook, to: &parts)
        ItemSearchBlob.appendOptional(funFact, to: &parts)
        ItemSearchBlob.appendOptional(hobbies, to: &parts)
        ItemSearchBlob.appendEntityRefs(typefaces, to: &parts)
        ItemSearchBlob.appendEntityRefs(typeFoundries, to: &parts)
        return parts
    }
}

extension StudioMeta {
    func searchTerms() -> [String] {
        var parts: [String] = []
        ItemSearchBlob.appendEntityRefs(work, to: &parts)
        ItemSearchBlob.appendEntityRefs(team, to: &parts)
        return parts
    }
}

extension FoundryMeta {
    func searchTerms() -> [String] {
        var parts: [String] = []
        ItemSearchBlob.appendOptional(description, to: &parts)
        ItemSearchBlob.appendOptional(category, to: &parts)
        ItemSearchBlob.appendEntityRef(geography, to: &parts)
        ItemSearchBlob.appendOptional(foundedYear, to: &parts)
        ItemSearchBlob.appendEntityRefs(foundersDesigners, to: &parts)
        ItemSearchBlob.appendOptional(priceRange, to: &parts)
        ItemSearchBlob.appendStrings(licensingTypes, to: &parts)
        ItemSearchBlob.appendOptional(designPhilosophy, to: &parts)
        ItemSearchBlob.appendStrings(popularFonts, to: &parts)
        ItemSearchBlob.appendStrings(specialisation, to: &parts)
        ItemSearchBlob.appendStrings(customServices, to: &parts)
        ItemSearchBlob.appendOptional(social, to: &parts)
        ItemSearchBlob.appendOptional(email, to: &parts)
        ItemSearchBlob.appendOptional(thoughts, to: &parts)
        ItemSearchBlob.appendStrings(distribution, to: &parts)
        ItemSearchBlob.appendEntityRefs(typefaces, to: &parts)
        ItemSearchBlob.appendEntityRefs(websites, to: &parts)
        ItemSearchBlob.appendEntityRefs(creatives, to: &parts)
        return parts
    }
}

extension PlaceMeta {
    func searchTerms() -> [String] {
        var parts: [String] = []
        ItemSearchBlob.appendOptional(city, to: &parts)
        ItemSearchBlob.appendOptional(country, to: &parts)
        return parts
    }
}
