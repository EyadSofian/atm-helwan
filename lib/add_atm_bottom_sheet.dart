import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_provider.dart';
import 'atm_model.dart';

class AddAtmBottomSheet extends StatefulWidget {
  const AddAtmBottomSheet({super.key});

  @override
  State<AddAtmBottomSheet> createState() => _AddAtmBottomSheetState();
}

class _AddAtmBottomSheetState extends State<AddAtmBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _bank = '';
  AtmStatus _selectedStatus = AtmStatus.working;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final provider = context.read<AppProvider>();
    final (success, errorMsg) = await provider.addNewAtm(
      name: _name,
      bank: _bank,
      status: _selectedStatus,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إضافة الـ ATM بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg ?? 'حدث خطأ غير متوقع'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch provider to listen to `isSubmitting` state
    final provider = context.watch<AppProvider>();

    return Padding(
      // Padding handles adjusting the bottom sheet when the keyboard appears
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'إضافة ATM جديد',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'سيتم تسجيل موقع الـ ATM تلقائياً باستخدام موقعك الحالي.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'اسم الـ ATM أو الموقع',
                  hintText: 'مثال: بنك مصر - شارع راغب',
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'مطلوب إدخال الاسم' : null,
                onSaved: (val) => _name = val!.trim(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'اسم البنك',
                  hintText: 'مثال: البنك الأهلي',
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'مطلوب إدخال البنك' : null,
                onSaved: (val) => _bank = val!.trim(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AtmStatus>(
                value: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'الحالة الحالية',
                  border: OutlineInputBorder(),
                ),
                items: AtmStatus.values.map((status) {
                  return DropdownMenuItem<AtmStatus>(
                    value: status,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon(status.key),
                            color: statusColor(status.key), size: 18),
                        const SizedBox(width: 8),
                        Text(status.label),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: provider.isSubmitting
                    ? null
                    : (val) {
                        if (val != null) setState(() => _selectedStatus = val);
                      },
                validator: (val) => val == null ? 'الرجاء اختيار الحالة' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: provider.isSubmitting ? null : _submit,
                child: provider.isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'إضافة',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
