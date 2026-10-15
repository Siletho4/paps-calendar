import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'repository_service.dart';

class MeetingDetailsPage extends StatelessWidget {
  final PSCMeeting meeting;
  const MeetingDetailsPage({super.key, required this.meeting});

  Future<void> launchTargetPage(BuildContext context, String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open page: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageUrl = meeting.documents['page'] ?? 'https://papsrepository.africanunion.org';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meeting Details", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0D47A1),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meeting.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  Row(children: [const Icon(Icons.gavel, size: 18, color: Colors.blueGrey), const SizedBox(width: 8), Expanded(child: Text("Chairing Country: ${meeting.chairingCountry}"))]),
                  const SizedBox(height: 8),
                  Row(children: [const Icon(Icons.tag, size: 18, color: Colors.blueGrey), const SizedBox(width: 8), Expanded(child: Text("Reference: ${meeting.reference}"))]),
                  const SizedBox(height: 8),
                  Row(children: [const Icon(Icons.calendar_today, size: 18, color: Colors.blueGrey), const SizedBox(width: 8), Expanded(child: Text("Date: ${meeting.date.day}/${meeting.date.month}/${meeting.date.year}"))]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (meeting.subjects.isNotEmpty) ...[
              const Text("Subjects:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6.0,
                runSpacing: 2.0,
                children: meeting.subjects.map((sub) => Chip(label: Text(sub, style: const TextStyle(fontSize: 12)))).toList(),
              ),
              const SizedBox(height: 20),
            ],
            const Text("Summary:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(meeting.summary, style: TextStyle(color: Colors.grey[800], height: 1.4)),
            const SizedBox(height: 30),
            
            // TARGET LINK BUTTON: Direct connection routing mechanism
            Card(
              color: Colors.blue[50],
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFF0D47A1), width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.article, color: Color(0xFF0D47A1), size: 28),
                title: const Text("View All Meeting Documents", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                subtitle: const Text("Opens the specific repository page containing the English, French, and Arabic PDFs for this assembly."),
                trailing: const Icon(Icons.open_in_new, color: Color(0xFF0D47A1)),
                onTap: () => launchTargetPage(context, pageUrl),
              ),
            ),
          ],
        ),
      ),
    );
  }
}