import 'dart:io';

class AppConfig {
  final bool saleEnabled;
  final DateTime? saleEndDate;
  final String adBannerId;
  final String adInterstitialId;
  final String appTitle;
  final String nextAppText;
  final String nextAppUrl;
  final int regularPrice;
  final int salePrice;
  final bool nextAppEnabled;
  final String premiumProductId;
  final String platformAppId;
  final String appId;
  final String questionsUrl;
  final String githubRepo;

  AppConfig({
    required this.saleEnabled,
    this.saleEndDate,
    required this.adBannerId,
    required this.adInterstitialId,
    required this.appTitle,
    required this.nextAppText,
    required this.nextAppUrl,
    required this.regularPrice,
    required this.salePrice,
    required this.nextAppEnabled,
    required this.premiumProductId,
    required this.platformAppId,
    required this.appId,
    this.questionsUrl = '',
    this.githubRepo = '',
  });

  factory AppConfig.defaults() => AppConfig(
    saleEnabled: false,
    adBannerId: '',
    adInterstitialId: '',
    appTitle: 'Study App',
    nextAppText: '',
    nextAppUrl: '',
    regularPrice: 390,
    salePrice: 190,
    nextAppEnabled: false,
    premiumProductId: 'unlock_premium',
    platformAppId: '',
    appId: '',
    questionsUrl: '',
    githubRepo: '',
  );

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    DateTime? endDate;
    if (json['sale_end_date'] != null && json['sale_end_date'].toString().isNotEmpty) {
      endDate = DateTime.tryParse(json['sale_end_date'].toString());
    }

    // Platform specific fields
    String banner = '';
    String inter = '';
    String nextUrl = '';
    String premiumId = '';
    String platformId = '';
    
    if (Platform.isIOS) {
      banner = json['ios_ad_banner']?.toString() ?? '';
      inter = json['ios_ad_inter']?.toString() ?? '';
      nextUrl = json['ios_next_app_url']?.toString() ?? '';
      premiumId = json['ios_premium_id']?.toString() ?? '';
      platformId = json['ios_id']?.toString() ?? '';
    } else {
      banner = (json['android_ad_banner'] ?? json['andoroid_ad_banner'])?.toString() ?? '';
      inter = (json['android_ad_inter'] ?? json['andoroid_ad_inter'])?.toString() ?? '';
      nextUrl = (json['android_next_app_url'] ?? json['andoroid_next_app_url'])?.toString() ?? '';
      premiumId = (json['android_premium_id'] ?? json['andoroid_premium_id'])?.toString() ?? '';
      platformId = (json['android_id'] ?? json['andoroid_id'])?.toString() ?? '';
    }

    return AppConfig(
      saleEnabled: json['sale_enabled'] == true || json['sale_enabled'] == 1 || json['sale_enabled']?.toString() == '1',
      saleEndDate: endDate,
      adBannerId: banner,
      adInterstitialId: inter,
      appTitle: json['app_name']?.toString() ?? '',
      nextAppText: json['next_app_text']?.toString() ?? '',
      nextAppUrl: nextUrl,
      regularPrice: int.tryParse(json['regular_price']?.toString() ?? '') ?? 390,
      salePrice: int.tryParse(json['sale_price']?.toString() ?? '') ?? 190,
      nextAppEnabled: json['next_app_enabled'] == true || json['next_app_enabled'] == 1 || json['next_app_enabled']?.toString() == '1',
      premiumProductId: premiumId.isNotEmpty ? premiumId : 'unlock_premium',
      platformAppId: platformId,
      appId: json['app_id']?.toString() ?? '',
      questionsUrl: json['questions_url']?.toString() ?? '',
      githubRepo: json['github_repo']?.toString() ?? '',
    );
  }

  bool get isSaleActive {
    if (!saleEnabled) return false;
    if (saleEndDate == null) return true;
    return DateTime.now().isBefore(saleEndDate!);
  }
}

class Quiz {
  final String question;
  final bool isCorrect;
  final String explanation;
  final String? imagePath;
  final String category;

  Quiz({
    required this.question,
    required this.isCorrect,
    required this.explanation,
    this.imagePath,
    required this.category,
  });

  factory Quiz.fromJson(Map<String, dynamic> json) {
    dynamic img = json['image_path'];
    String? finalImg;
    if (img != null && img != 'null' && img != '') {
      finalImg = img.toString();
    }

    // Handle is_correct as "〇" / "×" or bool or int
    bool correctValue = false;
    dynamic rawCorrect = json['is_correct'] ?? json['isCorrect'];
    if (rawCorrect == '〇' || rawCorrect == '○') {
      correctValue = true;
    } else if (rawCorrect == '×' || rawCorrect == 'x' || rawCorrect == 'X') {
      correctValue = false;
    } else if (rawCorrect is bool) {
      correctValue = rawCorrect;
    } else if (rawCorrect is num) {
      correctValue = rawCorrect == 1;
    }

    return Quiz(
      question: (json['question'] as String? ?? '').replaceAll('\n', ''),
      isCorrect: correctValue,
      explanation: json['explanation'] as String? ?? '',
      imagePath: finalImg,
      category: json['category'] as String? ?? '',
    );
  }
}

class AppData {
  final AppConfig config;
  final Map<String, List<Quiz>> questions;
  final List<String> categoryOrder;

  AppData({
    required this.config,
    required this.questions,
    required this.categoryOrder,
  });

  factory AppData.fromJson(Map<String, dynamic> json) {
    final configMap = json['config'] as Map<String, dynamic>? ?? {};
    final questionsList = json['questions'] as List<dynamic>? ?? [];
    final (grouped, order) = _parseQuestions(questionsList);
    return AppData(
      config: AppConfig.fromJson(configMap),
      questions: grouped,
      categoryOrder: order,
    );
  }

  /// Build AppData from a questions-only JSON (GitHub) + separately loaded master config.
  factory AppData.fromQuestionsJson(
      Map<String, dynamic> json, AppConfig masterConfig) {
    final questionsList = json['questions'] as List<dynamic>? ?? [];
    final (grouped, order) = _parseQuestions(questionsList);
    return AppData(
      config: masterConfig,
      questions: grouped,
      categoryOrder: order,
    );
  }

  static (Map<String, List<Quiz>>, List<String>) _parseQuestions(
      List<dynamic> questionsList) {
    final Map<String, List<Quiz>> grouped = {};
    final List<String> order = [];
    for (var qJson in questionsList) {
      final quiz = Quiz.fromJson(qJson as Map<String, dynamic>);
      final category = quiz.category.trim().isEmpty ? 'Other' : quiz.category.trim();
      if (!grouped.containsKey(category)) {
        grouped[category] = [];
        order.add(category);
      }
      grouped[category]!.add(quiz);
    }
    return (grouped, order);
  }
}
