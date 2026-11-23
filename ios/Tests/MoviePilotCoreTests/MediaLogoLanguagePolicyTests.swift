import MoviePilotCore
import Testing

@Suite("MediaLogoLanguagePolicyTests")
struct MediaLogoLanguagePolicyTests {
  @Test("语言码归一化兼容地区变体与常见别名")
  func normalizesBaseLanguageCodes() {
    #expect(NativeMediaLogoLanguagePolicy.baseLanguageCode("zh") == "zh")
    #expect(NativeMediaLogoLanguagePolicy.baseLanguageCode("zh-CN") == "zh")
    #expect(NativeMediaLogoLanguagePolicy.baseLanguageCode("zh_TW") == "zh")
    #expect(NativeMediaLogoLanguagePolicy.baseLanguageCode("zh-Hans") == "zh")
    #expect(NativeMediaLogoLanguagePolicy.baseLanguageCode("en-US") == "en")
    #expect(NativeMediaLogoLanguagePolicy.baseLanguageCode("ja-JP") == "ja")
    #expect(NativeMediaLogoLanguagePolicy.baseLanguageCode("ko-KR") == "ko")
    #expect(NativeMediaLogoLanguagePolicy.baseLanguageCode("  ") == nil)
    #expect(NativeMediaLogoLanguagePolicy.baseLanguageCode(nil) == nil)
  }

  @Test("后端 metadata 决策按用户媒体语言设置动态匹配")
  func metadataDecisionMatchesUserMediaLanguage() {
    // 用户媒体语言为中文（zh / zh-TW）
    #expect(
      NativeMediaLogoLanguagePolicy.metadataDecision(
        logoLanguage: "zh-CN", preferredMediaLanguage: "zh") == .confirmedMatch)
    #expect(
      NativeMediaLogoLanguagePolicy.metadataDecision(
        logoLanguage: "zh", preferredMediaLanguage: "zh-TW") == .confirmedMatch)
    #expect(
      NativeMediaLogoLanguagePolicy.metadataDecision(
        logoLanguage: "en", preferredMediaLanguage: "zh") == .confirmedMismatch)
    #expect(
      NativeMediaLogoLanguagePolicy.metadataDecision(
        logoLanguage: "ja", preferredMediaLanguage: "zh") == .confirmedMismatch)

    // 用户媒体语言为英文（en / en-US）
    #expect(
      NativeMediaLogoLanguagePolicy.metadataDecision(
        logoLanguage: "en", preferredMediaLanguage: "en-US") == .confirmedMatch)
    #expect(
      NativeMediaLogoLanguagePolicy.metadataDecision(
        logoLanguage: "zh-CN", preferredMediaLanguage: "en") == .confirmedMismatch)

    // 旧后端未返回 logo_language -> 交由本地图像验证
    #expect(
      NativeMediaLogoLanguagePolicy.metadataDecision(
        logoLanguage: nil, preferredMediaLanguage: "zh") == .needsImageVerification)
    #expect(
      NativeMediaLogoLanguagePolicy.metadataDecision(
        logoLanguage: "", preferredMediaLanguage: "en") == .needsImageVerification)
  }

  @Test("旧后端本地文字识别策略随用户媒体语言动态切换")
  func evaluatesRecognizedLogoTextAgainstUserMediaLanguage() {
    // 媒体语言 = 中文：接受中文 Logo，拒绝英文/日文/韩文 Logo
    #expect(
      NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "野兽之心", preferredMediaLanguage: "zh", originalLanguage: "en"))
    #expect(
      !NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "THE ODYSSEY", preferredMediaLanguage: "zh", originalLanguage: "en"))
    #expect(
      !NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "進撃の巨人", preferredMediaLanguage: "zh", originalLanguage: "ja"))
    #expect(
      !NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "오징어 게임", preferredMediaLanguage: "zh", originalLanguage: "ko"))
    #expect(
      NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "", preferredMediaLanguage: "zh", originalLanguage: "zh"))
    #expect(
      !NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "", preferredMediaLanguage: "zh", originalLanguage: "en"))

    // 媒体语言 = 英文：接受英文 Logo，拒绝中文/日文/韩文 Logo
    #expect(
      NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "THE ODYSSEY", preferredMediaLanguage: "en", originalLanguage: "en"))
    #expect(
      !NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "野兽之心", preferredMediaLanguage: "en", originalLanguage: "en"))
    #expect(
      !NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "進撃の巨人", preferredMediaLanguage: "en", originalLanguage: "ja"))

    // 媒体语言 = 日文：接受日文假名/汉字 Logo，拒绝英文/韩文 Logo
    #expect(
      NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "進撃の巨人", preferredMediaLanguage: "ja", originalLanguage: "ja"))
    #expect(
      !NativeMediaLogoLanguagePolicy.evaluateRecognizedText(
        "ATTACK ON TITAN", preferredMediaLanguage: "ja", originalLanguage: "ja"))
  }
}
