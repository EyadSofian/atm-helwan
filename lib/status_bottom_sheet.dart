import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'atm_model.dart';
import 'app_provider.dart';

class StatusBottomSheet extends StatelessWidget {
  final AtmModel atm;

  const StatusBottomSheet({super.key, required this.atm});

  @override
  Widget build(BuildContext context) {
    final effectiveStatus = atm.effectiveStatus;
    final timeAgo = _formatTimeAgo(atm.lastUpdated);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ATM name
          Text(
            atm.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),

          // Current status chip
          _StatusChip(status: effectiveStatus),
          const SizedBox(height: 4),

          // Last updated
          Text(
            'آخر تحديث: $timeAgo',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),

          const Text(
            'بلّغ عن الحالة الحالية:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          // Report buttons
          _ReportButtons(atm: atm),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'دلوقتي';
    if (diff.inMinutes < 60) return 'من ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'من ${diff.inHours} ساعة';
    return 'من ${diff.inDays} يوم';
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final AtmStatus status;
  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case AtmStatus.working:
        return Colors.green;
      case AtmStatus.empty:
      case AtmStatus.broken:
        return Colors.red;
      case AtmStatus.crowded:
        return Colors.orange;
      case AtmStatus.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        status.label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: _color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ReportButtons extends StatefulWidget {
  final AtmModel atm;
  const _ReportButtons({required this.atm});

  @override
  State<_ReportButtons> createState() => _ReportButtonsState();
}

class _ReportButtonsState extends State<_ReportButtons> {
  bool _loading = false;

  Future<void> _report(AtmStatus status) async {
    setState(() => _loading = true);

    final provider = context.read<AppProvider>();
    final (result, message) = await provider.submitReport(
      atm: widget.atm,
      newStatus: status,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case SubmitResult.success:
        Navigator.of(context).pop();
        _showSnack(context, '✅ تم تحديث الحالة: ${status.label}',
            Colors.green);
        break;
      case SubmitResult.tooFar:
        _showSnack(context, message ?? 'أنت بعيد عن الـ ATM.',
            Colors.red);
        break;
      case SubmitResult.cooldownActive:
        _showSnack(context, message ?? 'استنى شوية قبل ما تبلّغ تاني.',
            Colors.orange);
        break;
      case SubmitResult.locationError:
        _showSnack(context, message ?? 'مش قادر يحدد موقعك.',
            Colors.red);
        break;
      case SubmitResult.firestoreError:
        _showSnack(context, message ?? 'فشل الإرسال، جرب تاني.',
            Colors.red);
        break;
    }
  }

  void _showSnack(BuildContext ctx, String msg, Color color) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final buttons = [
      (AtmStatus.working, Colors.green, Icons.check_circle_outline, 'متاح'),
      (AtmStatus.empty, Colors.red, Icons.money_off, 'فاضي'),
      (AtmStatus.crowded, Colors.orange, Icons.people, 'مزدحم'),
      (AtmStatus.broken, Colors.red[900]!, Icons.cancel_outlined, 'عطلان'),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: buttons
          .map(
            (btn) => ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: btn.$2,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(btn.$3, size: 18),
              label: Text(btn.$4),
              onPressed: () => _report(btn.$1),
            ),
          )
          .toList(),
    );
  }
}
