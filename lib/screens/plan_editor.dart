import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/meal_item.dart';
import '../models/user_meal_plan.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Result of [PlanEditorSheet].
class PlanEditResult {
  final String slot;
  final String? scheduledTime; // HH:mm
  final String? foodId;
  final String? customFoodName;
  final String? portionLabel;
  final String? notes;
  final bool clearScheduledTime;
  final bool clearFoodId;

  PlanEditResult({
    required this.slot,
    this.scheduledTime,
    this.foodId,
    this.customFoodName,
    this.portionLabel,
    this.notes,
    this.clearScheduledTime = false,
    this.clearFoodId = false,
  });
}

/// Bottom-sheet editor used by both "আজ" (add/edit a custom meal entry)
/// and any other surface that wants to drive the same flow.
class PlanEditorSheet extends StatefulWidget {
  final DateTime date;
  final UserMealPlan? existing;
  const PlanEditorSheet({super.key, required this.date, this.existing});

  /// Convenience: shows the sheet and returns the editor result, or
  /// `null` if the user dismissed without saving.
  static Future<PlanEditResult?> show(
    BuildContext context, {
    required DateTime date,
    UserMealPlan? existing,
  }) {
    return showModalBottomSheet<PlanEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (_) => PlanEditorSheet(date: date, existing: existing),
    );
  }

  @override
  State<PlanEditorSheet> createState() => _PlanEditorSheetState();
}

class _PlanEditorSheetState extends State<PlanEditorSheet> {
  late String _slot;
  TimeOfDay? _time;
  String? _foodId;
  String? _customFoodName;
  final _customFoodCtrl = TextEditingController();
  final _portionCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  List<MealItem> _foodSuggestions = [];
  String _search = '';
  bool _loadingFoods = false;
  bool _useFreeText = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _slot = e.slot;
      _foodId = e.foodId;
      _customFoodName = e.customFoodName;
      _useFreeText = _foodId == null && _customFoodName != null;
      _customFoodCtrl.text = _customFoodName ?? '';
      _portionCtrl.text = e.portionLabel ?? '';
      _notesCtrl.text = e.notes ?? '';
      final t = e.scheduledTime;
      if (t != null && t.isNotEmpty) {
        final parts = t.split(':');
        if (parts.length >= 2) {
          _time = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 0,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }
    } else {
      _slot = 'breakfast';
    }
    _loadFoods('');
  }

  @override
  void dispose() {
    _customFoodCtrl.dispose();
    _portionCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFoods(String q) async {
    setState(() => _loadingFoods = true);
    try {
      final results = await SupabaseService.searchFoods(q, limit: 15);
      if (!mounted) return;
      setState(() => _foodSuggestions = results);
    } catch (_) {
      // ignore — picker will just be empty
    } finally {
      if (mounted) setState(() => _loadingFoods = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.ink,
            onPrimary: AppColors.paper,
            surface: AppColors.paper,
            onSurface: AppColors.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool get _canSave {
    if (_useFreeText) {
      return _customFoodCtrl.text.trim().isNotEmpty;
    }
    return _foodId != null;
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(
      context,
      PlanEditResult(
        slot: _slot,
        scheduledTime: _time != null ? _formatTime(_time!) : null,
        foodId: _useFreeText ? null : _foodId,
        customFoodName:
            _useFreeText ? _customFoodCtrl.text.trim() : null,
        portionLabel:
            _portionCtrl.text.trim().isEmpty ? null : _portionCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        clearScheduledTime: _time == null && widget.existing != null,
        clearFoodId: _useFreeText && widget.existing?.foodId != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.graphite,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Overline(
                      widget.existing == null
                          ? 'নতুন খাবার যোগ করুন'
                          : 'খাবার সম্পাদনা',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('d MMM, EEEE', 'bn').format(widget.date),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 22),
                    _buildSlotPicker(),
                    const SizedBox(height: 16),
                    _buildTimeRow(),
                    const SizedBox(height: 22),
                    _buildFoodPicker(),
                    const SizedBox(height: 16),
                    _buildPortionRow(),
                    const SizedBox(height: 16),
                    _buildNotesRow(),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        if (widget.existing != null)
                          Expanded(
                            child: MonoButton(
                              label: 'মুছে ফেলুন',
                              leading: Icons.delete_outline,
                              variant: MonoButtonVariant.outline,
                              onPressed: () async {
                                final navigator = Navigator.of(context);
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: AppColors.paper,
                                    title: const Text('মুছে ফেলবেন?'),
                                    content: const Text('এই খাবারটি সরানো হবে।'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('বাতিল'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        style: TextButton.styleFrom(
                                            foregroundColor: Colors.red),
                                        child: const Text('মুছুন'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true || !mounted) return;
                                await SupabaseService.deleteUserMealPlan(
                                    widget.existing!.id);
                                if (!mounted) return;
                                navigator.pop(null);
                              },
                            ),
                          ),
                        if (widget.existing != null) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: MonoButton(
                            label: 'সংরক্ষণ',
                            leading: Icons.check,
                            onPressed: _canSave ? _save : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('কোন সময়?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in kSlotOptions)
              Pressable(
                onTap: () => setState(() => _slot = s),
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: _slot == s ? AppGradients.aurora : null,
                    color: _slot == s ? null : AppColors.chalk,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color:
                            _slot == s ? Colors.transparent : AppColors.graphite),
                  ),
                  child: Text(
                    slotLabelBn(s),
                    style: TextStyle(
                      color: _slot == s ? AppColors.paper : AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeRow() {
    return Row(
      children: [
        const Overline('সময়'),
        const SizedBox(width: 12),
        Pressable(
          onTap: _pickTime,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: _time != null ? AppGradients.aurora : null,
              color: _time != null ? null : AppColors.chalk,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _time != null ? Colors.transparent : AppColors.graphite),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 16,
                  color: _time != null ? AppColors.paper : AppColors.ink,
                ),
                const SizedBox(width: 6),
                Text(
                  _time != null ? _formatTime(_time!) : 'সময় বাছাই',
                  style: TextStyle(
                    color: _time != null ? AppColors.paper : AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_time != null) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'সময় মুছুন',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _time = null),
          ),
        ],
      ],
    );
  }

  Widget _buildFoodPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Overline('খাবার'),
            const Spacer(),
            Pressable(
              onTap: () => setState(() {
                _useFreeText = !_useFreeText;
                if (_useFreeText) {
                  _foodId = null;
                } else {
                  _customFoodCtrl.clear();
                }
              }),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: _useFreeText
                      ? AppGradients.aurora
                      : null,
                  color: _useFreeText
                      ? null
                      : AppColors.paper.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _useFreeText ? Colors.transparent : AppColors.graphite),
                ),
                child: Text(
                  _useFreeText ? 'তালিকা থেকে বাছাই' : 'নিজের নাম লিখুন',
                  style: TextStyle(
                    color: _useFreeText ? AppColors.paper : AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_useFreeText)
          TextField(
            controller: _customFoodCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            decoration: const InputDecoration(
              hintText: 'যেমন: ডাক্তারের প্রেসক্রিপশন অনুযায়ী ভাত',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
          )
        else ...[
          TextField(
            onChanged: (v) {
              _search = v;
              _loadFoods(v);
            },
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            decoration: const InputDecoration(
              hintText: 'খাবার খুঁজুন…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingFoods)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: LoadingMark(size: 24)),
            )
          else if (_foodSuggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _search.isEmpty
                    ? 'খাবার খুঁজতে টাইপ করুন'
                    : 'কিছু পাওয়া যায়নি — “নিজের নাম লিখুন” ব্যবহার করুন',
                style: const TextStyle(
                  color: AppColors.smoke,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _foodSuggestions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final f = _foodSuggestions[i];
                  final selected = _foodId == f.id;
                  return Pressable(
                    onTap: () => setState(() => _foodId = f.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: selected ? AppGradients.aurora : null,
                        color: selected ? null : AppColors.chalk,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? Colors.transparent : AppColors.graphite),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.nameBn,
                                  style: TextStyle(
                                    color: selected
                                        ? AppColors.paper
                                        : AppColors.ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${f.portionLabel ?? ''} · ${f.category}',
                                  style: TextStyle(
                                    color: selected
                                        ? AppColors.paper.withValues(alpha: 0.7)
                                        : AppColors.smoke,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            selected ? Icons.check_circle : Icons.circle_outlined,
                            color: selected
                                ? AppColors.paper
                                : AppColors.smoke,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildPortionRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('পরিমাণ (ঐচ্ছিক)'),
        const SizedBox(height: 8),
        TextField(
          controller: _portionCtrl,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          decoration: const InputDecoration(
            hintText: 'যেমন: ১ কাপ, ২ পিস, ১৫০ গ্রাম',
            prefixIcon: Icon(Icons.scale_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('নোট (ঐচ্ছিক)'),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
          decoration: const InputDecoration(
            hintText: 'ডাক্তারের নির্দেশনা বা অন্য কোনো নোট',
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(Icons.notes_outlined),
            ),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
