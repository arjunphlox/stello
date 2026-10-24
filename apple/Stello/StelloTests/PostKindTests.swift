import Testing
import Foundation
import SwiftData
@testable import Stello

// MARK: - Helpers

private func classify(
    _ urlString: String,
    html: String = "<html><head></head><body></body></html>",
    ogType: String? = nil,
    labels: [String] = []
) -> PageClassificationResult {
    let url = URL(string: urlString)!
    return PageClassifier.classify(
        html: html,
        baseURL: url,
        domain: url.host,
        title: "Some page",
        ogDescription: nil,
        ogType: ogType,
        collectionLabels: labels
    )
}

private func buildPost(
    _ urlString: String,
    platform: String,
    html: String = "",
    ogTitle: String? = nil,
    ogDescription: String? = nil,
    ogImage: String? = nil,
    ogType: String? = nil,
    syndication: PostReader.SyndicationOutcome? = nil
) -> PostExtraction {
    PostReader.build(
        sourceURL: URL(string: urlString)!,
        finalURL: nil,
        platform: platform,
        html: html,
        ogTitle: ogTitle,
        ogDescription: ogDescription,
        ogImageURL: ogImage.flatMap { URL(string: $0) },
        ogType: ogType,
        syndication: syndication
    )
}

private func syndication(_ json: String, status: Int? = 200) -> PostReader.SyndicationOutcome {
    PostReader.parseSyndication(data: Data(json.utf8), statusCode: status)
}

private func isTweet(_ outcome: PostReader.SyndicationOutcome) -> Bool {
    if case .tweet = outcome { return true }
    return false
}

private func isGone(_ outcome: PostReader.SyndicationOutcome) -> Bool {
    if case .gone = outcome { return true }
    return false
}

// MARK: - Fixtures

private let photoTweetJSON = """
{"__typename":"Tweet","id_str":"1453768926539317251","lang":"en",
 "text":"Four colour studies in blue &amp; orange https://t.co/AbC123xyz",
 "created_at":"2021-10-28T17:00:00.000Z",
 "user":{"id_str":"1","name":"Jane Doe","screen_name":"janedoe"},
 "mediaDetails":[
   {"type":"photo","media_url_https":"https://pbs.twimg.com/media/a.jpg","original_info":{"width":1200,"height":800}},
   {"type":"photo","media_url_https":"https://pbs.twimg.com/media/b.jpg","original_info":{"width":1200,"height":800}},
   {"type":"photo","media_url_https":"https://pbs.twimg.com/media/c.jpg","original_info":{"width":800,"height":1200}},
   {"type":"photo","media_url_https":"https://pbs.twimg.com/media/d.jpg","original_info":{"width":1000,"height":1000}}],
 "photos":[
   {"url":"https://pbs.twimg.com/media/a.jpg","width":1200,"height":800},
   {"url":"https://pbs.twimg.com/media/b.jpg","width":1200,"height":800},
   {"url":"https://pbs.twimg.com/media/c.jpg","width":800,"height":1200},
   {"url":"https://pbs.twimg.com/media/d.jpg","width":1000,"height":1000}]}
"""

private let videoTweetJSON = """
{"__typename":"Tweet","id_str":"1700000000000000000",
 "text":"gm https://t.co/Vid123",
 "created_at":"2023-09-08T09:30:00.000Z",
 "user":{"name":"Motion Lab","screen_name":"motionlab"},
 "mediaDetails":[
   {"type":"video","media_url_https":"https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/poster.jpg",
    "original_info":{"width":1920,"height":1080}}],
 "video":{"poster":"https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/poster.jpg"}}
"""

private let tombstoneJSON = """
{"__typename":"TweetTombstone","tombstone":{"text":{"text":"This Post is from an account that no longer exists."}}}
"""

// MARK: - Classification

@Suite("Post classification")
struct PostClassificationTests {

    @Test("A single post on each platform → post, with its platform")
    func eachPlatform() {
        let cases: [(String, String)] = [
            ("https://x.com/janedoe/status/1453768926539317251", "x"),
            ("https://twitter.com/janedoe/status/1453768926539317251?s=20", "x"),
            ("https://mobile.twitter.com/janedoe/status/1453768926539317251", "x"),
            ("https://www.instagram.com/p/C1a2B3c4D5e/", "instagram"),
            ("https://www.instagram.com/reel/C1a2B3c4D5e/", "instagram"),
            ("https://www.instagram.com/reels/C1a2B3c4D5e/", "instagram"),
            ("https://www.instagram.com/tv/C1a2B3c4D5e/", "instagram"),
            ("https://www.behance.net/gallery/123456/Brand-Identity", "behance"),
            ("https://dribbble.com/shots/123456-Desk-lamp", "dribbble"),
            ("https://www.pinterest.com/pin/123456789/", "pinterest"),
            ("https://in.pinterest.com/pin/123456789/", "pinterest"),
        ]
        for (url, platform) in cases {
            let result = classify(url)
            #expect(result.kind == .post, "\(url)")
            #expect(result.postPlatform == platform, "\(url)")
            #expect(result.productSource == nil, "\(url)")
        }
    }

    @Test("Profiles, feeds and boards are not posts")
    func nonPostSocialURLs() {
        for url in [
            "https://x.com/janedoe",
            "https://twitter.com/home",
            "https://www.instagram.com/stuffcool/",
            "https://www.behance.net/janedoe",
            "https://dribbble.com/janedoe",
            "https://www.pinterest.com/janedoe/desk-ideas/",
        ] {
            #expect(classify(url).kind != .post, "\(url)")
        }
    }

    @Test("A wishlisted post stays a product; Post never steals it")
    func wishlistStaysProduct() {
        let reel = classify("https://www.instagram.com/reel/C1a2B3c4D5e/", labels: ["Wishlist"])
        #expect(reel.kind == .product)
        #expect(reel.productSource == "instagram")
        #expect(reel.postPlatform == nil)
        #expect(classify("https://x.com/maker/status/1234567890", labels: ["wishlist"]).kind == .product)
        #expect(PageClassifier.postPlatform(
            url: URL(string: "https://x.com/maker/status/1234567890")!, collectionLabels: ["wishlist"]
        ) == nil)
    }

    @Test("A post beats og:type product; AI-art labels never decide the kind")
    func postOrderAndLabels() {
        #expect(classify("https://www.instagram.com/p/C1a2B3c4D5e/", ogType: "product").kind == .post)
        // Not a post. Since the Tool kind, a gen-ai label on a non-article page makes it a tool.
        // An AI-art label vetoes the gen-ai tool label: a Midjourney gallery page isn't a tool.
        #expect(classify("https://example.com/gallery/neon-koi", labels: ["gen-ai", "midjourney"]).kind == .link)
        #expect(classify("https://example.com/gallery/neon-koi", labels: ["gen-ai"]).kind == .tool)
        #expect(classify("https://x.com/janedoe/status/1", labels: ["gen-ai"]).kind == .post)
    }
}

// MARK: - X syndication

@Suite("Post readers: X syndication")
struct XSyndicationTests {

    @Test("Token: the embed widget's base-36 formula (values checked against node)")
    func token() {
        #expect(PostReader.base36String((20 / 1e15) * Double.pi) == "0.000000006dq1a2xwd93")
        #expect(PostReader.base36String((1_700_000_000_000_000_000 / 1e15) * Double.pi) == "44c.pgxmyurn")
        #expect(PostReader.syndicationToken(for: "20") == "6dq1a2xwd93")
        #expect(PostReader.syndicationToken(for: "1234567890") == "6iio5bzbwyw")
        #expect(PostReader.syndicationToken(for: "1700000000000000000") == "44cpgxmyurn")
        #expect(PostReader.syndicationToken(for: "1453768926539317251") == "3iv5e449nho")
        #expect(PostReader.syndicationToken(for: "not-a-number") == "a")
        #expect(PostReader.base36String(0) == "0")
        #expect(PostReader.base36String(36) == "10")
        #expect(PostReader.base36String(0.5) == "0.i")
    }

    @Test("Tweet id, handle and endpoint from the URL")
    func idAndEndpoint() {
        let url = URL(string: "https://x.com/janedoe/status/1453768926539317251/photo/1")!
        #expect(PostReader.tweetID(from: url) == "1453768926539317251")
        #expect(PostReader.handleFromXURL(url) == "janedoe")
        #expect(PostReader.handleFromXURL(URL(string: "https://x.com/i/status/1453768926539317251")!) == nil)
        #expect(PostReader.tweetID(from: URL(string: "https://x.com/janedoe")!) == nil)
        let endpoint = PostReader.syndicationURL(forTweetID: "1453768926539317251")?.absoluteString
        #expect(endpoint == "https://cdn.syndication.twimg.com/tweet-result?id=1453768926539317251&lang=en&token=3iv5e449nho")
    }

    @Test("Photo tweet: text (t.co + entities cleaned), author, date, 4 photos → carousel")
    func photoTweet() throws {
        let outcome = syndication(photoTweetJSON)
        #expect(isTweet(outcome))
        let extraction = buildPost(
            "https://x.com/janedoe/status/1453768926539317251",
            platform: "x",
            ogTitle: "JavaScript is not available.",
            syndication: outcome
        )
        let meta = extraction.meta
        #expect(meta.platform == "x")
        #expect(meta.text == "Four colour studies in blue & orange")
        #expect(meta.authorHandle == "janedoe")
        #expect(meta.author?.name == "Jane Doe")
        #expect(meta.mediaType == "carousel")
        #expect(meta.mediaCount == 4)
        let posted = try #require(meta.postedAt)
        #expect(posted == ISO8601DateFormatter().date(from: "2021-10-28T17:00:00Z"))
        #expect(extraction.imageURLs.map(\.absoluteString) == [
            "https://pbs.twimg.com/media/a.jpg", "https://pbs.twimg.com/media/b.jpg",
            "https://pbs.twimg.com/media/c.jpg", "https://pbs.twimg.com/media/d.jpg",
        ])
        #expect(meta.canonicalURL == "https://x.com/janedoe/status/1453768926539317251")
        #expect(meta.embedURL == "https://platform.twitter.com/embed/Tweet.html?id=1453768926539317251")
        #expect(extraction.title == "@janedoe: Four colour studies in blue & orange")
        #expect(extraction.isGone == false)
        #expect(meta.cardKindLine == "@janedoe")
    }

    @Test("Video tweet: poster as the image, mediaType video, count 1")
    func videoTweet() {
        let extraction = buildPost(
            "https://twitter.com/motionlab/status/1700000000000000000",
            platform: "x",
            syndication: syndication(videoTweetJSON)
        )
        #expect(extraction.meta.mediaType == "video")
        #expect(extraction.meta.mediaCount == 1)
        #expect(extraction.meta.text == "gm")
        #expect(extraction.imageURLs.count == 1)
        #expect(extraction.title == "@motionlab: gm")
    }

    @Test("Tombstone, 404 and an empty body are gone; garbage is unavailable")
    func goneAndUnavailable() {
        #expect(isGone(syndication(tombstoneJSON)))
        #expect(isGone(PostReader.parseSyndication(data: Data(), statusCode: 404)))
        #expect(isGone(syndication("")))
        #expect(isGone(syndication("{}")))
        if case .unavailable = syndication("<html>rate limited</html>") {} else { Issue.record("expected unavailable") }
        if case .unavailable = PostReader.parseSyndication(data: nil, statusCode: nil) {} else { Issue.record("expected unavailable") }

        let gone = buildPost(
            "https://x.com/janedoe/status/1",
            platform: "x",
            ogTitle: "Jane Doe (@janedoe) on X",
            syndication: syndication(tombstoneJSON)
        )
        #expect(gone.isGone)
        #expect(gone.meta.authorHandle == "janedoe")
    }

    @Test("og fallback when syndication is unavailable")
    func ogFallback() {
        let extraction = buildPost(
            "https://x.com/janedoe/status/1",
            platform: "x",
            ogTitle: #"Jane Doe on X: "Shipping the new type specimen today""#,
            ogImage: "https://pbs.twimg.com/media/og.jpg",
            syndication: .unavailable
        )
        #expect(extraction.meta.text == "Shipping the new type specimen today")
        #expect(extraction.meta.author?.name == "Jane Doe")
        #expect(extraction.meta.authorHandle == "janedoe") // from the URL
        #expect(extraction.meta.mediaType == "image")
        #expect(extraction.imageURLs.count == 1)
        #expect(extraction.title == "@janedoe: Shipping the new type specimen today")
    }
}

// MARK: - Instagram

@Suite("Post readers: Instagram og")
struct InstagramPostTests {

    @Test("Image post: handle, name, caption, date, one image")
    func imagePost() throws {
        let extraction = buildPost(
            "https://www.instagram.com/p/C1a2B3c4D5e/",
            platform: "instagram",
            ogTitle: #"Jane Doe on Instagram: "Golden hour on the rooftop with the new lens""#,
            ogDescription: #"1,234 likes, 56 comments - janedoe on March 3, 2025: "Golden hour on the rooftop with the new lens". "#,
            ogImage: "https://scontent.cdninstagram.com/v/t51/abc.jpg?oe=1"
        )
        let meta = extraction.meta
        #expect(meta.platform == "instagram")
        #expect(meta.authorHandle == "janedoe")
        #expect(meta.author?.name == "Jane Doe")
        #expect(meta.text == "Golden hour on the rooftop with the new lens")
        #expect(meta.mediaType == "image")
        #expect(meta.mediaCount == 1)
        #expect(meta.embedURL == "https://www.instagram.com/p/C1a2B3c4D5e/embed")
        let posted = try #require(meta.postedAt)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let day = utc.dateComponents([.year, .month, .day], from: posted)
        #expect(day.year == 2025 && day.month == 3 && day.day == 3)
        #expect(extraction.imageURLs.count == 1)
        #expect(extraction.title == "@janedoe: Golden hour on the rooftop with the new…")
    }

    @Test("og:video or og:type video → video")
    func videoPost() {
        let html = #"<html><head><meta property="og:video" content="https://scontent.cdninstagram.com/v/clip.mp4"></head></html>"#
        let withVideoTag = buildPost(
            "https://www.instagram.com/p/C1a2B3c4D5e/",
            platform: "instagram",
            html: html,
            ogTitle: #"Motion Lab on Instagram: "Loop""#,
            ogImage: "https://scontent.cdninstagram.com/v/poster.jpg"
        )
        #expect(withVideoTag.meta.mediaType == "video")

        let withOGType = buildPost(
            "https://www.instagram.com/p/C1a2B3c4D5e/",
            platform: "instagram",
            ogTitle: #"Motion Lab on Instagram: "Loop""#,
            ogImage: "https://scontent.cdninstagram.com/v/poster.jpg",
            ogType: "video.other"
        )
        #expect(withOGType.meta.mediaType == "video")
        #expect(withOGType.meta.authorHandle == nil)
        #expect(withOGType.meta.cardKindLine == nil)
        #expect(withOGType.title == "Motion Lab: Loop")
    }
}

// MARK: - Behance / Dribbble / Pinterest

@Suite("Post readers: Behance / Dribbble / Pinterest")
struct OtherPostReaderTests {

    @Test("Behance: oEmbed author + handle; the work title loses its boilerplate")
    func behance() {
        let extraction = PostReader.build(
            sourceURL: URL(string: "https://www.behance.net/gallery/123456/Brand-Identity")!,
            finalURL: nil, platform: "behance", html: "",
            ogTitle: "Brand Identity for Foo on Behance",
            ogDescription: "A full identity system for Foo.",
            ogImageURL: URL(string: "https://mir-s3-cdn-cf.behance.net/project_modules/a.jpg"),
            ogType: nil,
            oembed: PostOEmbedInfo(
                title: "Brand Identity for Foo", authorName: "Jane Doe",
                authorURL: "https://www.behance.net/janedoe", thumbnailURL: nil
            )
        )
        #expect(extraction.meta.author?.name == "Jane Doe")
        #expect(extraction.meta.authorHandle == "janedoe")
        #expect(extraction.meta.text == "A full identity system for Foo.")
        #expect(extraction.title == "Brand Identity for Foo")
        #expect(PostReader.behanceOEmbedURL(for: URL(string: "https://www.behance.net/gallery/1/x?tracking=1")!)?.absoluteString
                == "https://www.behance.net/services/oembed?url=https%3A%2F%2Fwww.behance.net%2Fgallery%2F1%2Fx")
    }

    @Test("Dribbble: 'by Name on Dribbble' gives the author and the shot title")
    func dribbble() {
        let extraction = buildPost(
            "https://dribbble.com/shots/123456-Desk-lamp",
            platform: "dribbble",
            ogTitle: "Desk lamp by Jane Doe on Dribbble",
            ogImage: "https://cdn.dribbble.com/users/1/screenshots/1/lamp.png"
        )
        #expect(extraction.meta.author?.name == "Jane Doe")
        #expect(extraction.title == "Desk lamp")
        #expect(extraction.meta.mediaType == "image")
    }

    @Test("Pinterest: boilerplate description names the pinner, not the text")
    func pinterest() {
        let extraction = buildPost(
            "https://www.pinterest.com/pin/123456789/",
            platform: "pinterest",
            ogTitle: "Pin on Interiors",
            ogDescription: "This Pin was discovered by Jane Doe. Discover (and save!) your own Pins on Pinterest.",
            ogImage: "https://i.pinimg.com/736x/a.jpg"
        )
        #expect(extraction.meta.author?.name == "Jane Doe")
        #expect(extraction.meta.text == nil)
        #expect(extraction.title == "Pin on Interiors") // no text → original title
    }
}

// MARK: - AI art

@Suite("Post AI art")
struct PostAIArtTests {

    @Test("Collection labels flag AI art, with the model when the label names one")
    func labels() {
        #expect(PostReader.aiArtSignal(labels: ["Midjourney"], tags: [], text: nil)
                == AIArtSignal(isAIArt: true, model: "Midjourney"))
        #expect(PostReader.aiArtSignal(labels: ["nijijourney"], tags: [], text: nil).model == "Midjourney")
        #expect(PostReader.aiArtSignal(labels: ["Gen AI"], tags: [], text: nil)
                == AIArtSignal(isAIArt: true, model: nil))
        #expect(PostReader.aiArtSignal(labels: ["ai-art", "dall-e"], tags: [], text: nil).model == "DALL·E")
        #expect(PostReader.aiArtSignal(labels: ["wishlist", "typography"], tags: [], text: nil).isAIArt == false)
    }

    @Test("A tag flags AI art too")
    func tag() {
        #expect(PostReader.aiArtSignal(labels: [], tags: ["stable-diffusion"], text: nil)
                == AIArtSignal(isAIArt: true, model: "Stable Diffusion"))
    }

    @Test("Midjourney params in the text flag AI art as Midjourney")
    func params() {
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "neon koi pond --ar 16:9 --v 6")
                == AIArtSignal(isAIArt: true, model: "Midjourney"))
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "foggy tower —style raw").isAIArt)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "--sref 12345 --stylize 250").isAIArt)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "--chaos 20").isAIArt)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "--niji 6 cat").isAIArt)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "a --variant of the logo").isAIArt == false)
        #expect(PostReader.aiArtSignal(labels: [], tags: [], text: "I love this art").isAIArt == false)
        // A generic label + a model named in the text.
        #expect(PostReader.aiArtSignal(labels: ["gen-ai"], tags: [], text: "made with Midjourney").model == "Midjourney")
    }

    @Test("Prompt: after 'prompt:' / 'Prompt —', else the sentence with the params")
    func promptExtraction() {
        #expect(PostReader.extractPrompt(from: "New piece! Prompt: a neon koi pond at night, ukiyo-e style --ar 3:2")
                == "a neon koi pond at night, ukiyo-e style --ar 3:2")
        #expect(PostReader.extractPrompt(from: #"Prompt — "misty pine forest, morning light""#)
                == "misty pine forest, morning light")
        #expect(PostReader.extractPrompt(from: "Made this today. a brutalist tower in fog, cinematic --ar 2:3 --v 6\n#midjourney")
                == "a brutalist tower in fog, cinematic --ar 2:3 --v 6")
        #expect(PostReader.extractPrompt(from: "just vibes") == nil)
        #expect(PostReader.extractPrompt(from: nil) == nil)
    }

    @Test("applyAIArt: rule-read prompt replaces a guess; no signal clears the flag")
    func applyAIArt() {
        var meta = PostMeta()
        meta.text = "Made this today. a brutalist tower in fog --ar 2:3"
        meta.prompt = "old guess"
        meta.promptIsGuess = true
        PostReader.applyAIArt(to: &meta, labels: [], tags: [])
        #expect(meta.isAIArt)
        #expect(meta.aiModel == "Midjourney")
        #expect(meta.prompt == "a brutalist tower in fog --ar 2:3")
        #expect(meta.promptIsGuess == false)

        var plain = PostMeta()
        plain.text = "Golden hour on the rooftop"
        plain.isAIArt = true
        PostReader.applyAIArt(to: &plain, labels: [], tags: [])
        #expect(plain.isAIArt == false)
        #expect(plain.aiModel == nil)
    }

    @Test("Enrichment flags a labelled post; the fallback enricher leaves the prompt empty")
    @MainActor
    func enrichmentPass() async throws {
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)

        var meta = PostMeta()
        meta.platform = "instagram"
        meta.authorHandle = "janedoe"
        meta.text = "Brutalist library at dusk #aiart"
        let item = Item(title: "@janedoe: Brutalist library at dusk #aiart", kind: ItemKind.post.rawValue)
        item.setMetadata(meta)
        let label = Stello.Tag(name: "midjourney", category: "collection", weight: 1.0)
        context.insert(item)
        context.insert(label)
        label.item = item
        try context.save()

        await EnrichmentService.applyPostAIArtIfNeeded(item: item, enricher: RuleBasedFallbackEnricher())

        let after = try #require(item.postMeta())
        #expect(after.isAIArt)
        #expect(after.aiModel == "Midjourney")
        #expect(after.prompt == nil)
        #expect(after.promptIsGuess == false)
    }
}

// MARK: - Title rule

@Suite("Post title rule")
struct PostTitleRuleTests {

    private let longText = "Shipping the new type specimen today with every weight and the italics"

    @Test("Generic platform titles are recognised; real titles are not")
    func genericPatterns() {
        for title in [
            "Jane Doe (@janedoe) on X",
            #"Jane Doe on X: "hello""#,
            "Jane Doe on Twitter",
            #"Jane Doe on Twitter: "hello""#,
            #"Jane Doe on Instagram: "hello""#,
            "Jane Doe (@janedoe) • Instagram photos and videos",
            "Instagram",
            "Behance",
            "Dribbble",
            "Pin on Interiors",
            "x.com",
            "",
        ] {
            #expect(PostReader.isGenericPostTitle(title), "\(title)")
        }
        #expect(PostReader.isGenericPostTitle("Brand Identity for Foo on Behance") == false)
        #expect(PostReader.isGenericPostTitle("Desk lamp") == false)
    }

    @Test("Each generic pattern becomes '@handle: first 8 words…'")
    func replacesGeneric() {
        let expected = "@janedoe: Shipping the new type specimen today with every…"
        for title in ["Jane Doe (@janedoe) on X", #"Jane Doe on X: "Shipping…""#, "Jane Doe on Twitter",
                      #"Jane Doe on Instagram: "Shipping…""#, "Behance", "Dribbble"] {
            #expect(PostReader.postTitle(currentTitle: title, handle: "janedoe", authorName: "Jane Doe", text: longText)
                    == expected, "\(title)")
        }
    }

    @Test("Short text keeps no ellipsis; no handle uses the author's name")
    func shortText() {
        #expect(PostReader.postTitle(currentTitle: "Jane Doe on X", handle: "janedoe", authorName: nil, text: "gm")
                == "@janedoe: gm")
        #expect(PostReader.postTitle(currentTitle: "Instagram", handle: nil, authorName: "Jane Doe", text: "New lamp drop")
                == "Jane Doe: New lamp drop")
        #expect(PostReader.textExcerpt("one two three four five six seven eight") == "one two three four five six seven eight")
        #expect(PostReader.textExcerpt("one, two, three, four, five, six, seven, eight, nine") == "one, two, three, four, five, six, seven, eight…")
    }

    @Test("No text falls back to the original title; a real title is kept")
    func noTextAndRealTitle() {
        #expect(PostReader.postTitle(currentTitle: "Jane Doe (@janedoe) on X", handle: "janedoe", authorName: nil, text: nil)
                == "Jane Doe (@janedoe) on X")
        #expect(PostReader.postTitle(currentTitle: "My favourite lamp", handle: "janedoe", authorName: nil, text: longText)
                == "My favourite lamp")
        #expect(PostReader.postTitle(currentTitle: "Desk lamp by Jane Doe on Dribbble", handle: nil, authorName: nil, text: nil)
                == "Desk lamp")
    }
}

// MARK: - Kind line, panel + search

@Suite("Post kind line + search")
struct PostKindLineTests {

    @Test("Kind line is '@handle', nothing without a handle")
    func kindLine() {
        var meta = PostMeta()
        #expect(meta.cardKindLine == nil)
        meta.authorHandle = "  "
        #expect(meta.cardKindLine == nil)
        meta.authorHandle = "janedoe"
        #expect(meta.cardKindLine == "@janedoe")
    }

    @Test("Item kind line, typed panel and search over author, handle, text and prompt")
    @MainActor
    func itemLevel() {
        var meta = PostMeta()
        meta.platform = "x"
        meta.author = EntityRef(name: "Jane Doe", slug: nil, kind: ItemKind.individual.rawValue)
        meta.authorHandle = "janedoe"
        meta.text = "Four colour studies"
        meta.isAIArt = true
        meta.prompt = "brutalist library at dusk"
        let item = Item(title: "Saved thing", kind: ItemKind.post.rawValue)
        item.setMetadata(meta)

        #expect(item.cardKindLine == "@janedoe")
        #expect(item.hasRichTypedPanel)
        #expect(item.typedTopMediaRoles.contains(ItemImageRole.gallery.rawValue))
        #expect(ItemFilter.apply([item], searchText: "jane doe", selectedTagNames: []).count == 1)
        #expect(ItemFilter.apply([item], searchText: "@janedoe", selectedTagNames: []).count == 1)
        #expect(ItemFilter.apply([item], searchText: "colour studies", selectedTagNames: []).count == 1)
        #expect(ItemFilter.apply([item], searchText: "brutalist library", selectedTagNames: []).count == 1)
    }
}
