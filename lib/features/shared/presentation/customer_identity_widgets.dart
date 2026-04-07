import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import 'package:teamcash/core/models/customer_identity_models.dart';
import 'package:teamcash/core/utils/formatters.dart';

class CustomerIdentityQrCard extends StatelessWidget {
  const CustomerIdentityQrCard({
    super.key,
    required this.token,
    required this.onCopyPayload,
  });

  final CustomerIdentificationToken token;
  final VoidCallback onCopyPayload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('client-identity-qr-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD1E3DC)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useColumn = constraints.maxWidth < 520;
          final qrBox = Container(
            width: 220,
            height: 220,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: _QrSymbol(
              key: const ValueKey('client-identity-qr-symbol'),
              data: token.qrPayload,
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  Chip(
                    label: Text(
                      token.isPreview ? 'Preview QR' : 'Live customer QR',
                    ),
                  ),
                  Chip(label: Text(token.phoneE164)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Quick identification',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Staff can scan this in the mobile app later. While Chrome is the active dev target, the same payload can be copied and pasted into Staff > Scan.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF52606D),
                ),
              ),
              const SizedBox(height: 12),
              _IdentityDetailLine(label: 'Customer', value: token.displayName),
              _IdentityDetailLine(label: 'Wallet ID', value: token.customerId),
              _IdentityDetailLine(
                label: 'Generated',
                value: formatDateTime(token.generatedAt.toLocal()),
              ),
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('client-identity-qr-payload'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE6DED1)),
                ),
                child: Text(
                  token.compactPayload,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('client-identity-copy-payload'),
                    onPressed: onCopyPayload,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy QR payload'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.phone_android_outlined, size: 18),
                    label: Text('Chrome fallback uses ${token.phoneE164}'),
                  ),
                ],
              ),
            ],
          );

          return useColumn
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [qrBox, const SizedBox(height: 18), details],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    qrBox,
                    const SizedBox(width: 18),
                    Expanded(child: details),
                  ],
                );
        },
      ),
    );
  }
}

class ResolvedCustomerIdentityCard extends StatelessWidget {
  const ResolvedCustomerIdentityCard({
    super.key,
    required this.identifier,
    required this.onClear,
  });

  final ResolvedCustomerIdentifier identifier;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('staff-resolved-customer-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC9D8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  identifier.cameFromQr
                      ? 'Resolved from TeamCash QR'
                      : 'Phone normalized for operator flow',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('staff-resolved-customer-clear'),
                onPressed: onClear,
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (identifier.displayName case final displayName?)
            _IdentityDetailLine(label: 'Customer', value: displayName),
          _IdentityDetailLine(label: 'Phone', value: identifier.phoneE164),
          if (identifier.customerId case final customerId?)
            _IdentityDetailLine(label: 'Wallet ID', value: customerId),
          _IdentityDetailLine(
            label: 'Source',
            value: identifier.cameFromQr
                ? identifier.isPreview
                      ? 'Preview QR payload'
                      : 'Live client QR payload'
                : 'Manual phone entry',
          ),
        ],
      ),
    );
  }
}

class _IdentityDetailLine extends StatelessWidget {
  const _IdentityDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Color(0xFF52606D),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _QrSymbol extends StatelessWidget {
  const _QrSymbol({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final qrImage = QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
    );

    return CustomPaint(
      painter: _QrPainter(qrImage),
      child: const SizedBox.expand(),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.qrImage);

  final QrImage qrImage;

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = Colors.white;
    final darkPaint = Paint()..color = const Color(0xFF183A2D);
    canvas.drawRect(Offset.zero & size, lightPaint);

    final moduleCount = qrImage.moduleCount;
    final moduleSize = size.shortestSide / moduleCount;
    for (var row = 0; row < moduleCount; row++) {
      for (var col = 0; col < moduleCount; col++) {
        if (!qrImage.isDark(row, col)) {
          continue;
        }

        final rect = Rect.fromLTWH(
          col * moduleSize,
          row * moduleSize,
          moduleSize,
          moduleSize,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(moduleSize * 0.18)),
          darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) {
    return oldDelegate.qrImage != qrImage;
  }
}
