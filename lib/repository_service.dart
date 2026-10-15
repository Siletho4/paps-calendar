import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class PSCMeeting {
  final String title;
  final String summary;
  final DateTime date;
  final String reference;
  final String chairingCountry;
  final List<String> subjects;
  final Map<String, String> documents;

  PSCMeeting({
    required this.title,
    required this.summary,
    required this.date,
    required this.reference,
    required this.chairingCountry,
    required this.subjects,
    required this.documents,
  });
}

class RepositoryService {
  static const String _host = 'papsrepository.africanunion.org';
  static const String _baseUrl = 'https://papsrepository.africanunion.org';
  static const int _pageSize = 100;

  static Future<List<PSCMeeting>> fetchMeetings() async {
    final meetingsByKey = <String, PSCMeeting>{};
    final currentYear = DateTime.now().year;

    final queries = <String>[
      '',
      'Peace and Security Council',
      'PSC',
      'PSC/PR/COMM',
      'PSC/PR/BR',
      'PSC/MIN/COMM',
      'Communique',
      'Press Statement',
      'Briefing',
      'Meeting',
      'AUPSC Calendar',
      'PSC Calendar',
      'Peace and Security Council Calendar',
      'Monthly Programme',
      'Monthly Programme of Work',
      'Programme of Work',
      'Provisional Programme of Work',
      'Calendar of Activities',
      'PSC Activities',
      'Upcoming Meetings',
      'Future Meetings',
      'Agenda',
      for (int year = 2004; year <= currentYear + 5; year++) 'PSC $year',
      for (int year = 2004; year <= currentYear + 5; year++)
        'Peace and Security Council $year',
      for (int year = currentYear; year <= currentYear + 5; year++)
        'AUPSC Calendar $year',
      for (int year = currentYear; year <= currentYear + 5; year++)
        'Programme of Work $year',
      for (int year = currentYear; year <= currentYear + 5; year++)
        'Provisional Programme of Work $year',
    ];

    for (final query in queries) {
      final meetings = await _fetchMeetingsForQuery(query);

      for (final meeting in meetings) {
        meetingsByKey[_meetingKey(meeting)] = meeting;
      }
    }

    final futureMeetings = await _fetchUpcomingAupscCalendarMeetings();

    for (final meeting in futureMeetings) {
      meetingsByKey[_meetingKey(meeting)] = meeting;
    }

    final meetings = meetingsByKey.values.toList();
    meetings.sort((a, b) => b.date.compareTo(a.date));

    return meetings;
  }

  static String _meetingKey(PSCMeeting meeting) {
    return '${meeting.title}-${meeting.date.toIso8601String()}'
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static Future<List<PSCMeeting>> _fetchMeetingsForQuery(String query) async {
    final meetings = <PSCMeeting>[];

    int page = 0;
    int totalPages = 1;

    while (page < totalPages) {
      final uri = Uri.https(
        _host,
        '/server/api/discover/search/objects',
        {
          'query': query,
          'page': page.toString(),
          'size': _pageSize.toString(),
        },
      );

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) break;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final pageData = data['page'] as Map<String, dynamic>?;
      totalPages = pageData?['totalPages'] ?? 1;

      final objects =
          data['_embedded']?['searchResult']?['_embedded']?['objects']
              as List<dynamic>? ??
          [];

      for (final object in objects) {
        final item = object['_embedded']?['indexableObject'];
        if (item == null) continue;

        final type = item['type']?.toString().toLowerCase() ?? '';
        if (type != 'item') continue;

        final metadata = item['metadata'] as Map<String, dynamic>? ?? {};
        final meeting = _meetingFromItem(item, metadata);

        if (meeting != null && _looksLikePscMeeting(meeting)) {
          meetings.add(meeting);
        }
      }

      page++;
    }

    return meetings;
  }

  static Future<List<PSCMeeting>> _fetchUpcomingAupscCalendarMeetings() async {
    final meetingsByKey = <String, PSCMeeting>{};

    final urls = [
      'https://www.peaceau.org/en/home/events',
      'https://www.peaceau.org/en/events',
      'https://papsrepository.africanunion.org',
    ];

    for (final url in urls) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {'Accept': 'text/html'},
        );

        if (response.statusCode != 200) continue;

        final document = html_parser.parse(response.body);
        final pageText = _cleanText(document.body?.text ?? '');

        final meetings = _futureMeetingsFromText(
          pageText: pageText,
          sourceUrl: url,
        );

        for (final meeting in meetings) {
          meetingsByKey[_meetingKey(meeting)] = meeting;
        }
      } catch (_) {
        continue;
      }
    }

    return meetingsByKey.values.toList();
  }

  static List<PSCMeeting> _futureMeetingsFromText({
    required String pageText,
    required String sourceUrl,
  }) {
    final meetings = <PSCMeeting>[];
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    final matches = _findDateMatches(pageText);

    for (int i = 0; i < matches.length; i++) {
      final current = matches[i];
      final nextStart =
          i + 1 < matches.length ? matches[i + 1].start : pageText.length;

      final rawBlock = pageText.substring(
        current.start,
        nextStart.clamp(current.start, pageText.length),
      );

      final block = _cleanText(rawBlock);

      if (block.length < 8) continue;
      if (!_looksLikeUpcomingCalendarText(block)) continue;

      for (final date in current.dates) {
        if (date.isBefore(todayOnly)) continue;

        meetings.add(
          PSCMeeting(
            title: _titleFromFutureBlock(block, current.originalText),
            summary: block,
            date: date,
            reference: 'AUPSC Calendar',
            chairingCountry: 'AUPSC',
            subjects: const [
              'AUPSC Calendar',
              'Future Meeting',
              'Programme of Work',
            ],
            documents: {'page': sourceUrl},
          ),
        );
      }
    }

    return meetings;
  }

  static List<_CalendarDateMatch> _findDateMatches(String text) {
    final matches = <_CalendarDateMatch>[];
    final currentYear = DateTime.now().year;

    final months = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };

    final rangePatternWithYear = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|–|to)\s*(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]+)\s+(20\d{2})\b',
      caseSensitive: false,
    );

    for (final match in rangePatternWithYear.allMatches(text)) {
      final startDay = int.parse(match.group(1)!);
      final endDay = int.parse(match.group(2)!);
      final month = months[match.group(3)!.toLowerCase()];
      final year = int.parse(match.group(4)!);

      if (month == null) continue;

      matches.add(
        _CalendarDateMatch(
          start: match.start,
          originalText: match.group(0)!,
          dates: _dateRange(year, month, startDay, endDay),
        ),
      );
    }

    final rangePatternNoYear = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|–|to)\s*(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]+)\b',
      caseSensitive: false,
    );

    for (final match in rangePatternNoYear.allMatches(text)) {
      if (_isCoveredByExistingMatch(matches, match.start)) continue;

      final startDay = int.parse(match.group(1)!);
      final endDay = int.parse(match.group(2)!);
      final month = months[match.group(3)!.toLowerCase()];

      if (month == null) continue;

      final year = _bestYearForFutureDate(currentYear, month, startDay);

      matches.add(
        _CalendarDateMatch(
          start: match.start,
          originalText: match.group(0)!,
          dates: _dateRange(year, month, startDay, endDay),
        ),
      );
    }

    final singleDayMonthYear = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]+)\s+(20\d{2})\b',
      caseSensitive: false,
    );

    for (final match in singleDayMonthYear.allMatches(text)) {
      if (_isCoveredByExistingMatch(matches, match.start)) continue;

      final day = int.parse(match.group(1)!);
      final month = months[match.group(2)!.toLowerCase()];
      final year = int.parse(match.group(3)!);

      if (month == null) continue;

      matches.add(
        _CalendarDateMatch(
          start: match.start,
          originalText: match.group(0)!,
          dates: [DateTime(year, month, day)],
        ),
      );
    }

    final singleMonthDayYear = RegExp(
      r'\b([A-Za-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(20\d{2})\b',
      caseSensitive: false,
    );

    for (final match in singleMonthDayYear.allMatches(text)) {
      if (_isCoveredByExistingMatch(matches, match.start)) continue;

      final month = months[match.group(1)!.toLowerCase()];
      final day = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);

      if (month == null) continue;

      matches.add(
        _CalendarDateMatch(
          start: match.start,
          originalText: match.group(0)!,
          dates: [DateTime(year, month, day)],
        ),
      );
    }

    final singleDayMonthNoYear = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\b',
      caseSensitive: false,
    );

    for (final match in singleDayMonthNoYear.allMatches(text)) {
      if (_isCoveredByExistingMatch(matches, match.start)) continue;

      final day = int.parse(match.group(1)!);
      final month = months[match.group(2)!.toLowerCase()];

      if (month == null) continue;

      final year = _bestYearForFutureDate(currentYear, month, day);

      matches.add(
        _CalendarDateMatch(
          start: match.start,
          originalText: match.group(0)!,
          dates: [DateTime(year, month, day)],
        ),
      );
    }

    final singleMonthDayNoYear = RegExp(
      r'\b([A-Za-z]{3,9})\s+(\d{1,2})(?:st|nd|rd|th)?\b',
      caseSensitive: false,
    );

    for (final match in singleMonthDayNoYear.allMatches(text)) {
      if (_isCoveredByExistingMatch(matches, match.start)) continue;

      final month = months[match.group(1)!.toLowerCase()];
      final day = int.parse(match.group(2)!);

      if (month == null) continue;

      final year = _bestYearForFutureDate(currentYear, month, day);

      matches.add(
        _CalendarDateMatch(
          start: match.start,
          originalText: match.group(0)!,
          dates: [DateTime(year, month, day)],
        ),
      );
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  static int _bestYearForFutureDate(int currentYear, int month, int day) {
    final today = DateTime.now();
    final candidate = DateTime(currentYear, month, day);
    final todayOnly = DateTime(today.year, today.month, today.day);

    if (candidate.isBefore(todayOnly)) {
      return currentYear + 1;
    }

    return currentYear;
  }

  static List<DateTime> _dateRange(
    int year,
    int month,
    int startDay,
    int endDay,
  ) {
    final dates = <DateTime>[];

    if (endDay < startDay) {
      dates.add(DateTime(year, month, startDay));
      return dates;
    }

    for (int day = startDay; day <= endDay; day++) {
      dates.add(DateTime(year, month, day));
    }

    return dates;
  }

  static bool _isCoveredByExistingMatch(
    List<_CalendarDateMatch> matches,
    int start,
  ) {
    return matches.any(
      (existing) =>
          start >= existing.start &&
          start <= existing.start + existing.originalText.length,
    );
  }

  static PSCMeeting? _meetingFromItem(
    dynamic item,
    Map<String, dynamic> metadata,
  ) {
    final title = _firstMetadataValue(metadata, [
      'dc.title',
      'dcterms.title',
    ]);

    if (title.isEmpty) return null;

    final dateText = _firstMetadataValue(metadata, [
      'dc.date.issued',
      'dcterms.issued',
      'dc.date.available',
      'dc.date.accessioned',
    ]);

    final date = _parseDate(dateText);
    if (date == null) return null;

    final subjects = _allMetadataValues(metadata, [
      'dc.subject',
      'dcterms.subject',
    ]);

    final summary = _firstMetadataValue(
      metadata,
      [
        'dc.description.abstract',
        'dcterms.abstract',
        'dc.description',
      ],
      fallback: 'No summary available.',
    );

    final reference = _firstMetadataValue(
      metadata,
      [
        'dc.identifier.other',
        'dc.identifier.citation',
        'dc.relation.ispartofseries',
        'dcterms.identifier',
        'dc.identifier',
      ],
      fallback: _referenceFromTitle(title),
    );

    final chairingCountry = _firstMetadataValue(
      metadata,
      [
        'dc.contributor.chair',
        'dc.contributor.author',
        'dc.description.chair',
        'dc.coverage.spatial',
        'au.chairingCountry',
      ],
      fallback: 'Not listed',
    );

    final handleUrl = _firstMetadataValue(metadata, [
      'dc.identifier.uri',
      'dcterms.identifier.uri',
    ]);

    final uuid = item['uuid']?.toString() ?? '';

    final pageUrl = handleUrl.isNotEmpty
        ? handleUrl
        : uuid.isNotEmpty
            ? '$_baseUrl/items/$uuid'
            : _baseUrl;

    return PSCMeeting(
      title: title,
      summary: summary,
      date: date,
      reference: reference,
      chairingCountry: chairingCountry,
      subjects: subjects,
      documents: {'page': pageUrl},
    );
  }

  static bool _looksLikePscMeeting(PSCMeeting meeting) {
    final text = [
      meeting.title,
      meeting.summary,
      meeting.reference,
      meeting.chairingCountry,
      ...meeting.subjects,
    ].join(' ').toLowerCase();

    return text.contains('peace and security council') ||
        text.contains('aupsc') ||
        text.contains('psc/') ||
        text.contains(' psc ') ||
        text.startsWith('psc ') ||
        text.contains('communique') ||
        text.contains('communiqué') ||
        text.contains('press statement') ||
        text.contains('programme of work') ||
        text.contains('program of work') ||
        text.contains('calendar') ||
        text.contains('agenda') ||
        text.contains('upcoming') ||
        RegExp(r'\b\d{3,4}(st|nd|rd|th)\b').hasMatch(text);
  }

  static bool _looksLikeUpcomingCalendarText(String text) {
    final lower = text.toLowerCase();

    return lower.contains('peace and security council') ||
        lower.contains('aupsc') ||
        lower.contains('psc') ||
        lower.contains('meeting') ||
        lower.contains('briefing') ||
        lower.contains('session') ||
        lower.contains('programme of work') ||
        lower.contains('program of work') ||
        lower.contains('calendar') ||
        lower.contains('agenda');
  }

  static String _titleFromFutureBlock(String block, String dateText) {
    var title = block.replaceFirst(dateText, '').trim();

    title = title
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          RegExp(
            r'^(event|meeting|calendar|agenda)\s*[:\-]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    if (title.length > 120) {
      title = title.substring(0, 120).trim();
    }

    if (title.isEmpty) {
      return 'AUPSC Future Meeting';
    }

    return title;
  }

  static String _firstMetadataValue(
    Map<String, dynamic> metadata,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final values = metadata[key];

      if (values is List && values.isNotEmpty) {
        for (final valueObject in values) {
          if (valueObject is Map && valueObject['value'] != null) {
            final value = valueObject['value'].toString().trim();

            if (value.isNotEmpty) return value;
          }
        }
      }
    }

    return fallback;
  }

  static List<String> _allMetadataValues(
    Map<String, dynamic> metadata,
    List<String> keys,
  ) {
    final result = <String>[];

    for (final key in keys) {
      final values = metadata[key];

      if (values is List) {
        for (final valueObject in values) {
          if (valueObject is Map && valueObject['value'] != null) {
            final value = valueObject['value'].toString().trim();

            if (value.isNotEmpty && !result.contains(value)) {
              result.add(value);
            }
          }
        }
      }
    }

    return result;
  }

  static DateTime? _parseDate(String value) {
    final clean = value.trim();

    if (clean.isEmpty) return null;

    try {
      if (RegExp(r'^\d{4}$').hasMatch(clean)) {
        return DateTime(int.parse(clean), 1, 1);
      }

      if (RegExp(r'^\d{4}-\d{2}$').hasMatch(clean)) {
        final parts = clean.split('-');
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
      }

      return DateTime.parse(clean);
    } catch (_) {
      return null;
    }
  }

  static String _referenceFromTitle(String title) {
    final match = RegExp(
      r'\b(\d{3,4})(st|nd|rd|th)?\b',
      caseSensitive: false,
    ).firstMatch(title);

    if (match == null) return 'Not listed';

    return '${match.group(1)}th Meeting';
  }

  static String _cleanText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _CalendarDateMatch {
  final int start;
  final String originalText;
  final List<DateTime> dates;

  _CalendarDateMatch({
    required this.start,
    required this.originalText,
    required this.dates,
  });
}