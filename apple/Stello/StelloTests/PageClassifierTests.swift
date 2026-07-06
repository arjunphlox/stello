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
            ogDescription: nil,
            ogType: "profile"
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
            ogDescription: nil,
            ogType: "profile"
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

    // MARK: - Negative fixtures (Finding 1)

    @Test("Yoast @graph article with nested author Person stays link, not individual")
    func yoastArticleWithNestedAuthorPerson() {
        let html = """
        <html><head>
        <title>10 Tips for Better Type Design</title>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@graph": [
            {
              "@type": "Article",
              "headline": "10 Tips for Better Type Design",
              "author": {
                "@type": "Person",
                "name": "Jane Writer",
                "jobTitle": "Staff Writer",
                "address": {
                  "@type": "PostalAddress",
                  "addressLocality": "Brooklyn",
                  "addressRegion": "NY"
                }
              },
              "publisher": { "@type": "Organization", "name": "Design Weekly" }
            }
          ]
        }
        </script>
        </head><body><p>Article body about type design tips.</p></body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: base,
            domain: "designweekly.com",
            title: "10 Tips for Better Type Design",
            ogDescription: "A roundup of type design advice."
        )

        #expect(result.kind == .link)
        #expect(result.individualMeta == nil)
    }

    @Test("Publisher article with 'fonts' substring in title + Organization node stays link, not foundry")
    func publisherArticleWithFontsSubstring() {
        let html = """
        <html><head>
        <title>The 10 Best Free Fonts of 2026</title>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@graph": [
            {
              "@type": "Article",
              "headline": "The 10 Best Free Fonts of 2026"
            },
            {
              "@type": "Organization",
              "name": "Design Weekly"
            }
          ]
        }
        </script>
        </head><body><p>A roundup of the best free fonts this year.</p></body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: base,
            domain: "designweekly.com",
            title: "The 10 Best Free Fonts of 2026",
            ogDescription: "A roundup of the best free fonts this year."
        )

        #expect(result.kind == .link)
        #expect(result.individualMeta == nil)
    }

    @Test("Person referenced as @graph mainEntity → individual")
    func mainEntityPersonIsIndividual() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@graph": [
            {
              "@type": "ProfilePage",
              "mainEntity": { "@id": "https://people.example/jo#person" }
            },
            {
              "@type": "Person",
              "@id": "https://people.example/jo#person",
              "name": "Jo Glyph",
              "jobTitle": "Lettering Artist"
            }
          ]
        }
        </script>
        </head><body></body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: URL(string: "https://people.example/jo")!,
            domain: "people.example",
            title: "Jo Glyph",
            ogDescription: nil
        )

        #expect(result.kind == .individual)
        #expect(result.individualMeta?.currentRole == "Lettering Artist")
    }

    // MARK: - Social link fixtures (Finding 2)

    @Test("Twitter intent/share widget link is ignored, not assigned to xURL")
    func twitterIntentLinkIgnored() {
        let html = """
        <html><head>
        <meta property="og:type" content="profile">
        <script type="application/ld+json">
        { "@type": "Person", "name": "Alex Rivera" }
        </script>
        </head><body>
        <a href="https://twitter.com/intent/tweet?text=hello">Share on Twitter</a>
        </body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: base,
            domain: "example.com",
            title: "Alex Rivera",
            ogDescription: "Portfolio site."
        )

        #expect(result.kind == .individual)
        #expect(result.individualMeta?.xURL == nil)
    }

    @Test("Spoofed host (linkedin.com.evil.net) is rejected; legitimate linkedin.com subdomain is matched")
    func spoofedHostRejectedLegitimateSubdomainMatched() {
        let html = """
        <html><head>
        <meta property="og:type" content="profile">
        <script type="application/ld+json">
        { "@type": "Person", "name": "Alex Rivera" }
        </script>
        </head><body>
        <a href="https://linkedin.com.evil.net/in/impersonator">LinkedIn (spoofed)</a>
        <a href="https://business.linkedin.com/some-page">LinkedIn Business</a>
        </body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: base,
            domain: "example.com",
            title: "Alex Rivera",
            ogDescription: "Portfolio site."
        )

        #expect(result.kind == .individual)
        // The spoofed host never matches, so the legitimate business.linkedin.com subdomain wins.
        #expect(result.individualMeta?.linkedInURL == "https://business.linkedin.com/some-page")
    }

    @Test("rel=me link to an unrecognized host (GitHub) is left unset, not guessed as mastodon")
    func relMeUnrecognizedHostUnsetNotGuessed() {
        let html = """
        <html><head>
        <meta property="og:type" content="profile">
        <script type="application/ld+json">
        { "@type": "Person", "name": "Alex Rivera" }
        </script>
        <link rel="me" href="https://github.com/alexrivera">
        </head><body>
        <a href="https://instagram.com/alexrivera">Instagram</a>
        </body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: base,
            domain: "example.com",
            title: "Alex Rivera",
            ogDescription: "Portfolio site."
        )

        #expect(result.kind == .individual)
        #expect(result.individualMeta?.mastodon == nil)
        #expect(result.individualMeta?.instagramURL == "https://instagram.com/alexrivera")
    }

    @Test("rel=me link takes priority over a body anchor for the same platform")
    func relMeTakesPriorityOverBodyAnchor() {
        let html = """
        <html><head>
        <meta property="og:type" content="profile">
        <script type="application/ld+json">
        { "@type": "Person", "name": "Alex Rivera" }
        </script>
        </head><body>
        <a href="https://bsky.app/profile/someoneelse.bsky.social">Bluesky (someone else)</a>
        <a rel="me" href="https://bsky.app/profile/alexrivera.bsky.social">Bluesky (me)</a>
        </body></html>
        """

        let result = PageClassifier.classify(
            html: html,
            baseURL: base,
            domain: "example.com",
            title: "Alex Rivera",
            ogDescription: "Portfolio site."
        )

        #expect(result.kind == .individual)
        #expect(result.individualMeta?.bluesky == "https://bsky.app/profile/alexrivera.bsky.social")
    }
}
