import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/medicine.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'medicine_editor.dart';

/// "ওষুধ" tab — today's dose timeline + medicine catalogue CRUD.
///
/// The screen is designed for an elderly user:
///   • Every interactive surface is at least 56 dp tall.
///   • Bangla labels with English only where it helps (units, names).
///   • The "today" timeline is grouped into 4 fixed buckets so they
///     can see at a glance what's due now vs later.
///   • A single chunky "নিয়েছি" button per dose; no checkboxes
///     hidden under multiple menus.
class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key});

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen> {
  List<MedicineDose> _doses = [];
  List<Medicine> _medicines = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.medicineChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppEvents.medicineChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doses = await SupabaseService.getMedicineDosesForDate(DateTime.now());
      final meds = await SupabaseService.listMedicines();
      if (!mounted) return;
      setState(() {
        _doses = doses;
        _medicines = meds.where((m) => m.isActive).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({Medicine? existing}) async {
    final result = await MedicineEditorSheet.show(context, existing: existing);
    if (result == null) return;
    final ok = await applyMedicineEdit(result: result, existing: existing);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সংরক্ষণ করা যায়নি — আবার চেষ্টা করুন।')),
      );
      return;
    }
    AppEvents.notifyMedicineChanged();
  }

  Future<void> _toggleDose(MedicineDose dose, bool taken) async {
    // Optimistic update so the UI feels instant.
    setState(() {
      final i = _doses.indexWhere((d) =>
          d.medicineId == dose.medicineId && d.scheduledTime == dose.scheduledTime);
      if (i >= 0) {
        _doses[i] = _doses[i].copyWith(
          status: taken ? 'taken' : null,
          doseId: taken ? (_doses[i].doseId ?? 'optimistic') : null,
          takenAt: taken ? DateTime.now() : null,
        );
      }
    });
    try {
      await SupabaseService.markDose(
        medicineId: dose.medicineId,
        date: DateTime.now(),
        scheduledTime: dose.scheduledTime,
        status: taken ? 'taken' : 'skipped',
      );
      AppEvents.notifyMedicineChanged();
      // Re-pull so we get the canonical doseId / takenAt.
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('সংরক্ষণ ব্যর্থ: $e')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.ink,
          backgroundColor: AppColors.paper,
          onRefresh: _load,
          child: _loading
              ? const Center(child: LoadingMark(size: 36))
              : _error != null
                  ? _buildError()
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader()),
                        if (_doses.isEmpty && _medicines.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmpty(),
                          )
                        else
                          ..._buildDoseSlivers(),
                        const SliverToBoxAdapter(child: SizedBox(height: 120)),
                      ],
                    ),
        ),
      ),
    );
  }

  // ── Header / progress ────────────────────────────────────────────

  Widget _buildHeader() {
    final today = DateTime.now();
    final total = _doses.length;
    final done = _doses.where((d) => d.isTaken).length;
    final pct = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('আজকের ওষুধ'),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('d MMMM, EEEE', 'bn').format(today),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              _buildAddButton(),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 20),
            _buildProgressCard(done: done, total: total, pct: pct),
          ],
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return MonoButton(
      label: 'নতুন',
      leading: Icons.add,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      onPressed: () => _openEditor(),
    );
  }

  Widget _buildProgressCard({required int done, required int total, required double pct}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppGradients.aurora,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$done',
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          color: AppColors.paper,
                          height: 1.0,
                          letterSpacing: -1,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 4),
                        child: Text(
                          '/$total ডোজ',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.paper,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${(pct * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: AppColors.smoke,
              color: AppColors.paper,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            done == total
                ? 'আজকের সব ওষুধ নিয়েছেন — অভিনন্দন!'
                : 'আরও ${total - done}টি ওষুধ বাকি আছে।',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.paper,
            ),
          ),
        ],
      ),
    );
  }

  // ── Grouped timeline ─────────────────────────────────────────────

  List<Widget> _buildDoseSlivers() {
    final groups = <TimeBucket, List<MedicineDose>>{
      TimeBucket.morning: [],
      TimeBucket.noon: [],
      TimeBucket.afternoon: [],
      TimeBucket.night: [],
    };
    for (final d in _doses) {
      groups[d.bucket]?.add(d);
    }
    // Sort within each bucket by time.
    for (final list in groups.values) {
      list.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    }

    final slivers = <Widget>[];
    // Render in fixed order so the screen is predictable.
    for (final bucket in TimeBucket.values) {
      final items = groups[bucket]!;
      if (items.isEmpty) continue;
      slivers.add(SliverToBoxAdapter(child: _buildSectionHeader(bucket)));
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          sliver: SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => StaggeredReveal(
              index: i,
              child: _buildDoseTile(items[i]),
            ),
          ),
        ),
      );
    }

    // If there are active medicines but no doses scheduled today
    // (e.g. start date is tomorrow), show a list at the bottom so the
    // user can still see / edit them.
    final medicinesWithTodayDoses = _doses.map((d) => d.medicineId).toSet();
    final others = _medicines
        .where((m) => !medicinesWithTodayDoses.contains(m.id))
        .toList();
    if (others.isNotEmpty) {
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
      slivers.add(const SliverToBoxAdapter(child: _CatalogueSectionHeader()));
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
          sliver: SliverList.separated(
            itemCount: others.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _buildMedicineTile(others[i]),
          ),
        ),
      );
    }
    return slivers;
  }

  Widget _buildSectionHeader(TimeBucket bucket) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 24, 4),
      child: Row(
        children: [
          Icon(bucket.icon, size: 20, color: AppColors.ink),
          const SizedBox(width: 10),
          Text(
            bucket.labelBn,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 28,
            height: 1.4,
            color: AppColors.graphite,
          ),
        ],
      ),
    );
  }

  Widget _buildDoseTile(MedicineDose dose) {
    final isDone = dose.isTaken;
    final isMissed = dose.isMissed || (dose.isOverdue && !isDone);
    return Pressable(
      onTap: () => _toggleDose(dose, !isDone),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AnimatedContainer(
        duration: AppMotion.short,
        curve: AppMotion.standard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: isDone ? AppGradients.aurora : null,
          color: isDone ? null : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isDone ? Colors.transparent : (isMissed ? AppColors.text : AppColors.graphite),
            width: isMissed ? 1.8 : 1,
          ),
          boxShadow: isDone
              ? [
                  BoxShadow(
                    color: AppColors.cyan.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            _buildDoseClock(dose),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          dose.nameBn,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: isDone ? AppColors.paper : AppColors.ink,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (dose.strength != null && dose.strength!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDone
                                ? AppColors.paper.withValues(alpha: 0.18)
                                : AppColors.chalk,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            dose.strength!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isDone ? AppColors.paper : AppColors.smoke,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dose.doseLabel} · ${mealRelationBn(dose.mealRelation)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDone ? AppColors.paper : AppColors.smoke,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildToggle(isDone),
          ],
        ),
      ),
    );
  }

  Widget _buildDoseClock(MedicineDose dose) {
    final isDone = dose.isTaken;
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDone ? AppColors.paper.withValues(alpha: 0.15) : AppColors.chalk,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDone ? AppColors.paper.withValues(alpha: 0.2) : AppColors.graphite,
        ),
      ),
      child: Column(
        children: [
          Text(
            _hourLabel(dose.scheduledTime),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDone ? AppColors.paper : AppColors.ink,
              letterSpacing: -0.4,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _minuteLabel(dose.scheduledTime),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDone ? AppColors.paper : AppColors.smoke,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(bool isDone) {
    return AnimatedContainer(
      duration: AppMotion.short,
      width: 64,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDone ? AppColors.paper : AppColors.chalk,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDone ? AppColors.paper : AppColors.graphite,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: isDone ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                isDone ? 'নিয়েছি' : 'নিতে হবে',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isDone ? AppColors.ink : AppColors.smoke,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          AnimatedAlign(
            duration: AppMotion.short,
            curve: AppMotion.standard,
            alignment: isDone ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: isDone ? AppGradients.nebula : null,
                color: isDone ? null : AppColors.paper,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDone ? Colors.transparent : AppColors.graphite,
                ),
              ),
              child: Icon(
                isDone ? Icons.check : Icons.circle_outlined,
                size: 16,
                color: isDone ? AppColors.paper : AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Medicine catalogue tile ──────────────────────────────────────

  Widget _buildMedicineTile(Medicine m) {
    return Pressable(
      onTap: () => _openEditor(existing: m),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.graphite),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.chalk,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.graphite),
              ),
              child: Icon(
                medicineFormIcon(m.form),
                color: AppColors.ink,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.nameBn,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${m.doseLabel}${m.strength != null && m.strength!.isNotEmpty ? ' · ${m.strength}' : ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.smoke,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.ink),
          ],
        ),
      ),
    );
  }

  // ── Empty + error states ─────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: AppGradients.aurora,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.medication_outlined,
                size: 44,
                color: AppColors.paper,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'কোনো ওষুধ যোগ করা হয়নি',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'দৈনিক ওষুধের সময়সূচী এখানে যোগ করুন — প্রতিদিন এক নজরে দেখতে পাবেন।',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.smoke,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            MonoButton(
              label: 'নতুন ওষুধ যোগ করুন',
              leading: Icons.add,
              onPressed: () => _openEditor(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.ink),
            const SizedBox(height: 12),
            Text(
              'ত্রুটি: $_error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 16),
            MonoButton(label: 'আবার চেষ্টা', onPressed: _load),
          ],
        ),
      ),
    );
  }
}

class _CatalogueSectionHeader extends StatelessWidget {
  const _CatalogueSectionHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 0, 24, 0),
      child: Row(
        children: [
          Icon(Icons.medication_outlined, size: 18, color: AppColors.ink),
          SizedBox(width: 10),
          Text(
            'অন্যান্য ওষুধ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Divider(color: AppColors.graphite, height: 1),
          ),
        ],
      ),
    );
  }
}

// ── MedicineDose copyWith helper (private to this file) ─────────────
extension on MedicineDose {
  MedicineDose copyWith({
    String? doseId,
    String? status,
    DateTime? takenAt,
    bool clearTakenAt = false,
  }) {
    return MedicineDose(
      doseId: doseId ?? this.doseId,
      medicineId: medicineId,
      nameBn: nameBn,
      nameEn: nameEn,
      form: form,
      strength: strength,
      doseAmount: doseAmount,
      doseUnit: doseUnit,
      mealRelation: mealRelation,
      color: color,
      medicineNotes: medicineNotes,
      scheduledTime: scheduledTime,
      bucket: bucket,
      status: status ?? this.status,
      takenAt: clearTakenAt ? null : (takenAt ?? this.takenAt),
      note: note,
      isOverdue: isOverdue,
    );
  }
}

// ── small string helpers ───────────────────────────────────────────
String _hourLabel(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.isEmpty) return hhmm;
  return parts[0];
}

String _minuteLabel(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return '';
  return ':${parts[1]}';
}