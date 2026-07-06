import Testing
import Foundation
@testable import Stello

@Suite("PageClassifier")
struct PageClassifierTests {

    private let base = URL(string: "https://example.com/page")!

    @Test("Person JSON-LD → individual with role, location, bio, social")
    func personJSONLD() {
        let html = """
        <html><head>
        <meta property="og:description" content="Designer and letterer based in Portland.">
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Person",
          "name": "Alex Rivera",
          "jobTitle": "Type Designer",
          "address": {
            "@type": "PostalAddress",
            "addressLocality": "Portland",
            "addressRegion": "OR"
          }
        }
        </script>
        </head><body>
        <a href="https://instagram.com/alexrivera">Instagram</a>
        <a href="https://www.linkedin.com/in/alexrivera">LinkedIn</a>
        </body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: base,
            domain: "example.com",
            title: "Alex Rivera",
            ogDescription: "Designer and letterer based in Portland."
        )

        #expect(result.kind == .individual)
        #expect(result.individualMeta?.bio == "Designer and letterer based in Portland.")
        #expect(result.individualMeta?.currentRole == "Type Designer")
        #expect(result.individualMeta?.location?.name == "Portland, OR")
        #expect(result.individualMeta?.instagramURL == "https://instagram.com/alexrivera")
        #expect(result.individualMeta?.linkedInURL == "https://www.linkedin.com/in/alexrivera")
    }

    @Test("rel=me indie site → individual social URLs")
    func relMeIndieSite() {
        let html = """
        <html><head>
        <meta property="og:type" content="profile">
        <link rel="me" href="https://mastodon.social/@artist">
        <link rel="me" href="https://bsky.app/profile/artist.bsky.social">
        </head><body>
        <a rel="me" href="https://threads.net/@artist">Threads</a>
        <a href="https://x.com/artist">X</a>
        </body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: URL(string: "https://artist.example")!,
            domain: "artist.example",
            title: "Artist Portfolio",
            ogDescription: nil
        )

        #expect(result.kind == .individual)
        #expect(result.individualMeta?.mastodon == "https://mastodon.social/@artist")
        #expect(result.individualMeta?.bluesky == "https://bsky.app/profile/artist.bsky.social")
        #expect(result.individualMeta?.threads == "https://threads.net/@artist")
        #expect(result.individualMeta?.xURL == "https://x.com/artist")
    }

    @Test("Plain article stays link")
    func plainArticle() {
        let html = """
        <html><head>
        <meta property="og:type" content="article">
        <title>How Grid Layout Works</title>
        </head><body><p>Article body.</p></body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: base,
            domain: "example.com",
            title: "How Grid Layout Works",
            ogDescription: "A deep dive into CSS grid."
        )

        #expect(result.kind == .link)
        #expect(result.individualMeta == nil)
    }

    @Test("Organization with foundry signals → foundry")
    func foundryOrganization() {
        let html = """
        <html><head>
        <title>Klim Type Foundry</title>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Organization",
          "name": "Klim Type Foundry"
        }
        </script>
        </head><body></body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: URL(string: "https://klim.co.nz/fonts")!,
            domain: "klim.co.nz",
            title: "Klim Type Foundry",
            ogDescription: nil
        )

        #expect(result.kind == .foundry)
        #expect(result.individualMeta == nil)
    }

    @Test("Conflicting individual + foundry signals → link")
    func conflictingSignals() {
        let html = """
        <html><head>
        <meta property="og:type" content="profile">
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Organization",
          "name": "Acme Type Foundry"
        }
        </script>
        </head><body></body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: URL(string: "https://acme-typefoundry.com")!,
            domain: "acme-typefoundry.com",
            title: "Acme Type Foundry",
            ogDescription: nil
        )

        #expect(result.kind == .link)
        #expect(result.individualMeta == nil)
    }

    @Test("Organization without foundry keywords stays link")
    func organizationWithoutFoundryKeywords() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        { "@type": "Organization", "name": "Acme Corp" }
        </script>
        </head></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: base,
            domain: "acme.com",
            title: "Acme Corp",
            ogDescription: nil
        )

        #expect(result.kind == .link)
    }
}
