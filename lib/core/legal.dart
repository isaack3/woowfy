import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

const termsUrl = 'https://woowfy.com/terms';
const privacyUrl = 'https://woowfy.com/privacy';

/// "Al … aceptas los Términos y la Política de privacidad", con enlaces que abren en otra pestaña.
class LegalNotice extends StatefulWidget {
  const LegalNotice({super.key, required this.prefix});

  /// Por ejemplo "Al crear tu cuenta aceptas".
  final String prefix;

  @override
  State<LegalNotice> createState() => _LegalNoticeState();
}

class _LegalNoticeState extends State<LegalNotice> {
  late final _terms = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(termsUrl));
  late final _privacy = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(privacyUrl));

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const link = TextStyle(color: WoowfyColors.green, fontWeight: FontWeight.w700, decoration: TextDecoration.underline);
    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WoowfyColors.muted),
        children: [
          TextSpan(text: '${widget.prefix} los '),
          TextSpan(text: 'Términos y condiciones', style: link, recognizer: _terms),
          const TextSpan(text: ' y la '),
          TextSpan(text: 'Política de privacidad', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
