import XCTest
@testable import Newsflow

/// Testy dekodowania odpowiedzi PostgREST (format zgodny z widokami v_briefings / v_feed).
final class DecodingTests: XCTestCase {
    func testTimestampParsing() throws {
        XCTAssertNotNil(DateParsing.timestamp("2026-11-20T07:00:01.123456+00:00"))
        XCTAssertNotNil(DateParsing.timestamp("2026-11-20T07:00:01+00:00"))
        XCTAssertNotNil(DateParsing.timestamp("2026-11-20 07:00:01.5+00"))
        XCTAssertNotNil(DateParsing.timestamp("2026-11-20T07:00:01Z"))
        let a = try XCTUnwrap(DateParsing.timestamp("2026-11-20T07:00:01.250+00:00"))
        let b = try XCTUnwrap(DateParsing.timestamp("2026-11-20T07:00:01Z"))
        XCTAssertEqual(a.timeIntervalSince(b), 0.25, accuracy: 0.001)
    }

    func testBriefingDecoding() throws {
        let json = """
        [{"id":"7b4c1f0e-1111-4e2b-9c55-1f9e0d8a0001","briefing_date":"2026-11-20","edition":"ai-daily",
          "title":"Model X zmienia zasady","summary":"Lead.","text_content":"# T","trends":"Trendy.","stats":{},
          "sections":[{"position":0,"section":"headline","story_id":"s1","headline":"H","summary":"S",
            "why_it_matters":"W","practical_use":null,"discrepancies":null,"subcategory":"Agenci AI",
            "importance_score":7.45,"source_count":2,
            "sources":[{"content_item_id":"c1","title":"T","source":"OpenAI News","url":"https://openai.com/x"}]}],
          "chapters":[{"index":0,"title":"Intro","start_seconds":0,"duration_seconds":41.2,"audio_asset_id":"a1","story_ids":[]},
                      {"index":1,"title":"Model X","start_seconds":41.2,"duration_seconds":120,"audio_asset_id":"a2","story_ids":["s1"]}],
          "status":"delivered","items_considered":25,"items_analyzed":60,"items_rejected":30,
          "created_at":"2026-11-20T06:01:02.345678+00:00","email_sent_at":null,
          "audio_asset_id":"7b4c1f0e-1111-4e2b-9c55-1f9e0d8a0002","audio_path":"briefings/2026-11-20/x/full.mp3",
          "audio_duration_seconds":734.5,"my_position_seconds":null,"is_saved":false,
          "script":{"title":"t","description":"d","chapters":[
            {"kind":"intro","title":"Intro","story_ids":[],"text":"Dzień dobry.\n\nAudycję przygotowała i czyta sztuczna inteligencja."},
            {"kind":"headline","title":"Model X","story_ids":["s1"],"text":"Akapit pierwszy.\n\nAkapit drugi."}]}}]
        """.data(using: .utf8)!
        let rows = try JSONCoding.decoder.decode([Briefing].self, from: json)
        let b = try XCTUnwrap(rows.first)
        XCTAssertTrue(b.hasAudio)
        XCTAssertEqual(b.headline?.storyId, "s1")
        XCTAssertEqual(b.chapter(forStory: "s1")?.startSeconds, 41.2)
        XCTAssertEqual(b.sections.first?.sources.first?.source, "OpenAI News")
        XCTAssertEqual(Track.from(b)?.chapters.count, 2)
        // Okładka rozdziału wg podkategorii tematu; intro = styl briefingu
        XCTAssertEqual(b.style(for: b.chapters[1]).slug, "agents")
        XCTAssertEqual(b.style(for: b.chapters[0]), .daily)
        XCTAssertEqual(b.scriptText(for: b.chapters[1]), "Akapit pierwszy.\n\nAkapit drugi.")
        XCTAssertEqual(Track.from(b)?.texts.count, 2)
    }

    func testCoverStyleLookup() {
        XCTAssertEqual(CoverStyle.forKey("policy-safety").word, "Regulacje")
        XCTAssertEqual(CoverStyle.forKey("Agenci AI").slug, "agents")
        XCTAssertEqual(CoverStyle.forKey(nil), .daily)
        XCTAssertEqual(CoverStyle.forKey("nieznana"), .daily)
        XCTAssertEqual(CoverStyle.categories.count, 15)
    }

    func testFeedItemDecoding() throws {
        let json = """
        [{"id":"7b4c1f0e-1111-4e2b-9c55-1f9e0d8a0003","title":"Tytuł","original_title":"Title","original_url":"https://e.com/a",
          "author":null,"published_at":"2026-11-20T05:00:00+00:00","collected_at":"2026-11-20T05:10:00.1+00:00",
          "visibility":"public","extraction_status":"extracted","analysis_status":"analyzed",
          "source_id":"7b4c1f0e-1111-4e2b-9c55-1f9e0d8a0004","source_name":"OpenAI News","source_type":"rss",
          "summary":"S","key_points":["a","b"],"practical_value":null,"why_it_matters":"W",
          "claims":[{"text":"najlepszy","type":"marketing"}],"completeness":"complete","source_language":"en",
          "importance_score":7.45,"reliability_score":8,"subcategory_slug":"llm","subcategory_name":"Modele językowe i LLM",
          "story_id":null,"story_item_count":null,"story_source_count":null,"my_rating":1,"is_saved":true}]
        """.data(using: .utf8)!
        let item = try XCTUnwrap(try JSONCoding.decoder.decode([FeedItem].self, from: json).first)
        XCTAssertEqual(item.reliabilityScore, 8)
        XCTAssertEqual(item.claims?.first?.label, "Deklaracja producenta")
        XCTAssertTrue(item.isSaved)
    }

    func testSourceKindFeedURL() {
        XCTAssertEqual(SourceKind.youtube.feedURL(from: "https://www.youtube.com/channel/UCbfYPyITQ-7l4upoX8nvctg"),
                       "https://www.youtube.com/feeds/videos.xml?channel_id=UCbfYPyITQ-7l4upoX8nvctg")
        XCTAssertEqual(SourceKind.reddit.feedURL(from: "r/LocalLLaMA"), "https://www.reddit.com/r/LocalLLaMA/top/.rss?t=day")
        XCTAssertEqual(SourceKind.medium.feedURL(from: "@karpathy"), "https://medium.com/feed/@karpathy")
        XCTAssertNil(SourceKind.youtube.feedURL(from: "@handle"))
    }

    func testClock() {
        XCTAssertEqual(Fmt.clock(734), "12:14")
        XCTAssertEqual(Fmt.clock(3725), "1:02:05")
        XCTAssertEqual(Fmt.sources(3), "3 źródła")
        XCTAssertEqual(Fmt.sources(5), "5 źródeł")
    }
}
