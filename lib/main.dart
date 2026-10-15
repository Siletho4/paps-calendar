import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'repository_service.dart';
import 'meeting_details.dart';

void main() {
  runApp(const PSCApp());
}

class PSCApp extends StatelessWidget {
  const PSCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Peace And Security Council Calendar',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2EC000)),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color appBarBackground = Color(0xFF1A5632);
  static const Color appBarText = Color(0xFFB4A269);

  List<PSCMeeting> allMeetings = [];
  List<PSCMeeting> filteredMeetings = [];

  DateTime selectedDay = DateTime.now();
  DateTime focusedDay = DateTime.now();
  bool isLoading = true;
  String? loadError;
  String currentSearchQuery = "";

  @override
  void initState() {
    super.initState();
    loadMeetings();
  }

  Future<void> loadMeetings() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final meetings = await RepositoryService.fetchMeetings();
      if (!mounted) return;

      setState(() {
        allMeetings = meetings;
        filteredMeetings = meetings;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loadError =
            'Could not load meetings. Check your internet connection and try again.';
        isLoading = false;
      });
    }
  }

  void filterSearch(String query) {
    currentSearchQuery = query.toLowerCase();

    setState(() {
      if (currentSearchQuery.isEmpty) {
        filteredMeetings = allMeetings;
      } else {
        filteredMeetings = allMeetings.where((m) {
          final titleMatch = m.title.toLowerCase().contains(currentSearchQuery);
          final refMatch = m.reference.toLowerCase().contains(
            currentSearchQuery,
          );
          final subjectMatch = m.subjects
              .join(' ')
              .toLowerCase()
              .contains(currentSearchQuery);

          return titleMatch || refMatch || subjectMatch;
        }).toList();
      }
    });
  }

  List<PSCMeeting> getEventsForDay(DateTime day) {
    return filteredMeetings.where((m) {
      return m.date.year == day.year &&
          m.date.month == day.month &&
          m.date.day == day.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = getEventsForDay(selectedDay);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarBackground,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(3),
              child: Image.asset(
                'assets/app_logo.png',
                fit: BoxFit.contain,
                semanticLabel: 'African Union logo',
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Peace And Security Council Calendar',
                style: TextStyle(
                  color: appBarText,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: loadMeetings,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: TextField(
                    onChanged: filterSearch,
                    decoration: InputDecoration(
                      hintText: 'Search by title, reference, or subject...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                  ),
                ),

                TableCalendar<PSCMeeting>(
                  firstDay: DateTime.utc(2004, 1, 1),
                  lastDay: DateTime.utc(DateTime.now().year + 5, 12, 31),
                  focusedDay: focusedDay,
                  selectedDayPredicate: (d) => isSameDay(selectedDay, d),
                  eventLoader: getEventsForDay,
                  calendarStyle: const CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: Colors.lightBlue,
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Color(0xFF2EC000),
                      shape: BoxShape.circle,
                    ),
                    markerDecoration: BoxDecoration(
                      color: Color(0xFFACAC4D),
                      shape: BoxShape.circle,
                    ),
                  ),
                  onDaySelected: (selected, focused) {
                    setState(() {
                      selectedDay = selected;
                      focusedDay = focused;
                    });
                  },
                ),

                const Divider(thickness: 2),

                Container(
                  width: double.infinity,
                  color: appBarBackground.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    "Selected Date: ${selectedDay.day}/${selectedDay.month}/${selectedDay.year} (Found: ${dayEvents.length} items)",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                Expanded(
                  child: filteredMeetings.isEmpty
                      ? const Center(child: Text("No meetings found."))
                      : ListView.builder(
                          itemCount: dayEvents.isNotEmpty
                              ? dayEvents.length
                              : filteredMeetings.length,
                          itemBuilder: (context, index) {
                            final meeting = dayEvents.isNotEmpty
                                ? dayEvents[index]
                                : filteredMeetings[index];

                            return Card(
                              color: dayEvents.isNotEmpty
                                  ? Colors.white
                                  : Colors.amber[50],
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                title: Text(
                                  meeting.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  "Ref: ${meeting.reference}\nChair: ${meeting.chairingCountry}\nDate: ${meeting.date.day}/${meeting.date.month}/${meeting.date.year}",
                                ),
                                isThreeLine: true,
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          MeetingDetailsPage(meeting: meeting),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
