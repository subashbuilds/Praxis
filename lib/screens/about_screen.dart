import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_version.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

Future<void> _openRepository(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(kGitHubRepository),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // A device without a browser still gets a copyable link below.
  }
  if (opened) return;
  await Clipboard.setData(const ClipboardData(text: kGitHubRepository));
  messenger.showSnackBar(
    const SnackBar(content: Text('No browser available. Link copied.')),
  );
}

const kTermsText = '''PRAXIS TERMS OF SERVICE

Last updated: 5 November 2026

1. What Praxis is
Praxis is a local coding workbench. Project files, chats, provider keys and integration tokens are stored on your device. Praxis does not provide a model, host your projects or operate a developer account for you.

2. Your accounts and keys
You supply your own model provider keys and, if you connect them, your own GitHub and Vercel accounts. You are responsible for complying with those providers' terms, usage limits and prices. Model calls made with your key are billed by that provider, not by Praxis.

3. Your content
You keep ownership of the code and content you create. You grant Praxis no licence to it beyond what is needed to read and write files on your device. When you choose Push or Deploy, the selected files are sent to GitHub or Vercel at your direction.

4. Acceptable use
Do not use Praxis to break the law, infringe another person's rights, or violate a provider's terms. Do not use it to distribute malware or to access systems you are not authorised to access.

5. Third-party services
GitHub, Vercel and model providers are independent services. Praxis cannot guarantee their availability, output, or continued free tiers. Review changes before pushing and deployments before sharing them.

6. No warranty
Praxis is provided "as is" without warranties of any kind. The agent can make mistakes. Keep backups of important work. To the maximum extent permitted by law, the authors are not liable for lost data, lost profits, or indirect damages arising from use of the app.

7. Changes and termination
These terms may be updated with a new app release. You can stop using Praxis at any time and erase local data from Settings → Data.

8. Contact
Questions about these terms can be raised in the project's issue tracker.
''';

const kPrivacyText = '''PRAXIS PRIVACY POLICY

Last updated: 5 November 2026

Praxis is built to keep your work on your phone.

Data Praxis stores on this device
• Project files and their history in the app's documents directory.
• Your chat transcript for each project.
• Model provider keys, GitHub and Vercel tokens, and account labels in app preferences.
• Token usage counts and a local push baseline.
This data is not uploaded to a Praxis server. Praxis has no account system and no telemetry.

Network requests
When you send a message, Praxis sends the conversation and relevant file contents directly to the model provider you selected, using the endpoint and key you configured. When you Push or Deploy, the selected files are sent directly to GitHub or Vercel. The provider's privacy policy governs that data.

Photos and files
Files you attach are copied into the project's attachments folder and become part of that project. Remove the project to remove them.

Deleting your data
Settings → Data → Reset Praxis deletes projects, chats, keys and tokens from this device. Uninstalling the app also removes its local storage. Export any project you want to keep first.

Children
Praxis is a developer tool and is not directed to children.

Changes
This policy may be updated with a new app release. The current version is always available from Settings → About.
''';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  IconAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Text('About', style: Txt.title),
                  const Spacer(),
                  const Wordmark(size: 13, showMark: false),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.page, Sp.x5, Sp.page, Sp.x10),
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 36),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Praxis', style: Txt.headline),
                          const SizedBox(height: 2),
                          Text('Version $kAppVersion ($kAppBuild)',
                              style: Txt.meta),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: Sp.x4),
                  Text(
                    'A local-first coding workbench for Android. Real files, a '
                    'real shell, a live preview, and an agent that edits the '
                    'project with your own model key. Praxis is open source and '
                    'lives on GitHub.',
                    style: Txt.bodySoft,
                  ),
                  const SizedBox(height: Sp.x4),
                  Text(
                    'No account. No telemetry. Your projects live in the app’s '
                    'documents directory and belong to you.',
                    style: Txt.meta.copyWith(height: 1.55),
                  ),
                  const SectionLabel('OPEN SOURCE'),
                  _AboutLink(
                    icon: Icons.fork_right_rounded,
                    title: 'Praxis on GitHub',
                    body:
                        '$kGitHubRepositoryLabel · source, issues and releases',
                    onTap: () => _openRepository(context),
                  ),
                  const SizedBox(height: 8),
                  _AboutLink(
                    icon: Icons.volunteer_activism_outlined,
                    title: 'Open-source project',
                    body:
                        'Praxis is developed in public. Contributions and bug '
                        'reports are welcome.',
                    onTap: () => _openRepository(context),
                  ),
                  const SectionLabel('LEGAL'),
                  _AboutLink(
                    icon: Icons.description_outlined,
                    title: 'Terms of Service',
                    body:
                        'How Praxis may be used, and the limits of its warranty.',
                    onTap: () => _openLegal(
                      context,
                      'Terms of Service',
                      kTermsText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _AboutLink(
                    icon: Icons.lock_outline_rounded,
                    title: 'Privacy Policy',
                    body: 'What stays on this device, and when data is sent.',
                    onTap: () => _openLegal(
                      context,
                      'Privacy Policy',
                      kPrivacyText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _AboutLink(
                    icon: Icons.code_rounded,
                    title: 'Open-source licences',
                    body: 'Flutter and the packages Praxis is built with.',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Praxis',
                      applicationVersion: kAppVersion,
                      applicationLegalese:
                          'Praxis is an independent local-first app. '
                          'Third-party packages retain their own licences.',
                    ),
                  ),
                  const SectionLabel('CREDITS'),
                  Text(
                    'Built with Flutter. Markdown previews use GitHub-flavoured '
                    'HTML with the markdown package; icons use flutter_svg; '
                    'archives use archive. Each package keeps its original licence.',
                    style: Txt.bodySoft,
                  ),
                  const SizedBox(height: Sp.x5),
                  const Hairline(),
                  const SizedBox(height: Sp.x3),
                  Text(
                    '© 2026 Praxis. Made for building on the device you carry.',
                    style: Txt.meta,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openLegal(BuildContext context, String title, String body) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LegalScreen(title: title, body: body),
    ));
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Panel(
        padding:
            const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x2 + 2),
        child: Row(
          children: [
            Icon(icon, size: 17, color: Pal.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Txt.label.copyWith(
                        color: Pal.text,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(body, style: Txt.meta.copyWith(fontSize: 9.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: Pal.textDim),
          ],
        ),
      ),
    );
  }
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  IconAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text(title, style: Txt.title)),
                  const Wordmark(size: 13, showMark: false),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.page, Sp.x4, Sp.page, Sp.x8),
                children: [
                  Text(
                    'Praxis $kAppVersion',
                    style: Txt.meta,
                  ),
                  const SizedBox(height: Sp.x3),
                  SelectableText(
                    body,
                    style: Txt.bodySoft.copyWith(
                      fontSize: 13,
                      height: 1.65,
                      color: Pal.textMuted,
                    ),
                  ),
                  const SizedBox(height: Sp.x8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
