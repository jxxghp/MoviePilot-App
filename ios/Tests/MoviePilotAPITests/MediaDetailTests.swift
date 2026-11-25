import Foundation
import MoviePilotAPI
import Testing

struct MediaDetailTests {
  @Test func decodesDoubanMovieDetailWithDictionaryAvatarsAndStringCredits() throws {
    let json = Data(
      """
      {
        "media_source": "douban",
        "media_id": "1292052",
        "douban_id": "1292052",
        "imdb_id": "tt0111161",
        "type": "电影",
        "title": "肖申克的救赎",
        "original_title": "The Shawshank Redemption",
        "year": "1994",
        "release_date": "1994-09-10",
        "runtime": 142,
        "poster_path": "https://img2.doubanio.com/view/photo/s_ratio_poster/public/p480747492.jpg",
        "backdrop_path": "",
        "overview": "一场谋杀案使银行家安迪蒙冤入狱。",
        "vote_average": 9.7,
        "genres": [{"id": "剧情", "name": "剧情"}, "犯罪"],
        "production_countries": [{"id": "美国", "name": "美国"}],
        "season_info": [],
        "directors": [
          {
            "id": "1047973",
            "name": "弗兰克·德拉邦特",
            "latin_name": "Frank Darabont",
            "avatar": {
              "large": "https://img1.doubanio.com/view/celebrity/raw/public/p230.jpg",
              "normal": "https://img1.doubanio.com/view/celebrity/s_ratio_celebrity/public/p230.jpg"
            },
            "roles": ["导演"],
            "uri": "douban://douban.com/celebrity/1047973?subject_id=27260441"
          }
        ],
        "actors": [
          {
            "id": "1054521",
            "name": "蒂姆·罗宾斯",
            "latin_name": "Tim Robbins",
            "character": "饰 安迪·杜佛兰",
            "avatar": {
              "large": "https://img1.doubanio.com/view/celebrity/raw/public/p17525.jpg",
              "normal": "https://img1.doubanio.com/view/celebrity/s_ratio_celebrity/public/p17525.jpg"
            },
            "roles": ["演员"],
            "uri": "douban://douban.com/celebrity/1054521?subject_id=27260442"
          },
          "摩根·弗里曼"
        ]
      }
      """.utf8)

    let detail = try JSONDecoder().decode(MediaDetailPayload.self, from: json)
    #expect(detail.mediaSource == "douban")
    #expect(detail.mediaID == "1292052")
    #expect(detail.doubanID == "1292052")
    #expect(detail.title == "肖申克的救赎")
    #expect(detail.genreNames == ["剧情", "犯罪"])
    #expect(detail.directors?.count == 1)
    #expect(detail.directors?.first?.displayName == "弗兰克·德拉邦特")
    #expect(
      detail.directors?.first?.artworkPath(forSource: "douban")
        == "https://img1.doubanio.com/view/celebrity/s_ratio_celebrity/public/p230.jpg")
    #expect(detail.actors?.count == 2)
    #expect(detail.actors?.first?.resolvedPersonID == 27_260_442)
    #expect(detail.actors?.first?.subtitle == "饰 安迪·杜佛兰")
    #expect(detail.actors?.last?.displayName == "摩根·弗里曼")

    let creditsEndpoint = MediaSourceEndpoint.creditsEndpoint(
      for: detail, fallbackSource: "douban", fallbackMediaID: "1292052", type: "电影")
    #expect(creditsEndpoint?.path == ["douban", "credits", "1292052", "电影"])

    let recEndpoints = MediaSourceEndpoint.recommendationEndpoints(
      for: detail, fallbackSource: "douban", fallbackMediaID: "1292052", type: "电影")
    #expect(recEndpoints.count == 1)
    #expect(recEndpoints.first?.path == ["douban", "recommend", "1292052", "电影"])
  }

  @Test func synthesizesDoubanTVSeasonsAndIgnoresNullSeasonInfoNumber() throws {
    let json = Data(
      """
      {
        "media_source": "douban",
        "media_id": "3541415",
        "douban_id": "3541415",
        "type": "电视剧",
        "title": "三体",
        "year": 2023,
        "season_info": [{"season_number": null, "name": "无效季"}],
        "seasons": {"1": [1, 2, 3, 4, 5, 6]},
        "season_years": {"1": "2023"}
      }
      """.utf8)

    let detail = try JSONDecoder().decode(MediaDetailPayload.self, from: json)
    #expect(detail.year == "2023")
    #expect(detail.seasonInfo?.isEmpty == true)
    #expect(detail.resolvedSeasons.count == 1)
    #expect(detail.resolvedSeasons.first?.seasonNumber == 1)
    #expect(detail.resolvedSeasons.first?.episodeCount == 6)
    #expect(detail.resolvedSeasons.first?.airDate == "2023")
  }

  @Test func decodesBangumiAndAniListPersonImageSetsAndRoutes() throws {
    let bangumiPersonJSON = Data(
      """
      {
        "source": "bangumi",
        "id": 4962,
        "name": "花泽香菜",
        "career": ["声优", "歌手"],
        "images": {
          "large": "https://lain.bgm.tv/pic/crt/l/1.jpg",
          "medium": "https://lain.bgm.tv/pic/crt/m/1.jpg"
        }
      }
      """.utf8)
    let bgmPerson = try JSONDecoder().decode(MediaPersonSummary.self, from: bangumiPersonJSON)
    #expect(bgmPerson.artworkPath == "https://lain.bgm.tv/pic/crt/m/1.jpg")
    #expect(bgmPerson.subtitle == "声优、歌手")
    #expect(
      MediaSourceEndpoint.personDetailEndpoint(source: "douban", personID: 27_260_442)?.path
        == ["douban", "person", "27260442"])
    #expect(
      MediaSourceEndpoint.personCreditsEndpoint(source: "bangumi", personID: 4962)?.path
        == ["bangumi", "person", "credits", "4962"])
    #expect(
      MediaSourceEndpoint.personDetailEndpoint(source: "anilist", personID: 95_001)?.path
        == ["anilist", "person", "95001"])
  }

  @Test func resolvesMultiSourceSummaryIdentityAndNormalizesMediaType() throws {
    let summaryJSON = Data(
      """
      {
        "media_source": "douban",
        "douban_id": "26752088",
        "type": "movie",
        "title": "我不是药神",
        "year": 2018
      }
      """.utf8)
    let item = try JSONDecoder().decode(MediaSummaryItem.self, from: summaryJSON)
    let identity = try #require(item.resolvedIdentity(fallbackSource: "douban"))
    #expect(identity.source == "douban")
    #expect(identity.mediaID == "26752088")
    #expect(identity.type == "电影")
    #expect(MediaSummaryItem.normalizeMediaType("剧集") == "电视剧")
    #expect(MediaSummaryItem.normalizeMediaType("未知") == nil)
  }
}
