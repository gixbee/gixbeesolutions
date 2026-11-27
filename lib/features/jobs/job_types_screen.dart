import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'pending_payments_screen.dart';
import '../billing/platform_plans_screen.dart';
import '../../repositories/events_repository.dart' show eventDate;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/matching_repository.dart';
import '../../repositories/talent_repository.dart';
import 'hiring_catalog.dart';
import 'seeker_profile_wizard.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Candidate career profiles (FRD: first 2 free Job Types, +₹50/mo after).
/// These prefs power Hire Employee matching — without them, employers cannot
/// notify you on the Alerts tab.
class JobTypesScreen extends ConsumerStatefulWidget {
  final VoidCallback? onCreatedHint;
  const JobTypesScreen({super.key, this.onCreatedHint});

  @override
  ConsumerState<JobTypesScreen> createState() => _JobTypesScreenState();
}

class _JobTypesScreenState extends ConsumerState<JobTypesScreen> {
  List<Map<String, dynamic>> _prefs = [];
  Map<String, dynamic>? _talent;
  bool _loading = true;
  final Set<String> _updatingPreferences = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(matchingRepositoryProvider).listPreferences();
      Map<String, dynamic>? talent;
      try {
        talent = await ref.read(talentRepositoryProvider).getProfile();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _prefs = list;
        _talent = talent;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, 'Could not load profiles: $e',
          type: GxSnackType.error);
    }
  }

  int get _freeProfiles => _prefs.where((profile) =>
      profile['isPaid'] != true && profile['requiresCareerPlan'] != true).length;

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final wasEmpty = _prefs.isEmpty;
    var profile = existing;
    while (true) {
      if (!mounted) return;
      final saved = profile;
      final changed = await Navigator.push<SeekerProfileResult>(
        context,
        MaterialPageRoute(
          builder: (_) => SeekerProfileWizard(
            existing: saved == null
                ? null
                : {
                    ...saved,
                    'availableOn': _talent?['availableOn'],
                  },
            freeSlotsLeft: (2 - _freeProfiles).clamp(0, 2),
          ),
        ),
      );
      if (changed != null && mounted) {
        await _load();
        if (wasEmpty &&
            _prefs.isNotEmpty &&
            widget.onCreatedHint != null &&
            mounted) {
          showGxSnack(
            context,
            'Profile saved. Matching jobs are on the Jobs tab.',
            type: GxSnackType.success,
          );
        }
      }
      if (changed != SeekerProfileResult.createAnother) return;
      profile = null;
    }
  }

  Future<void> _delete(Map<String, dynamic> pref) async {
    final id = pref['id']?.toString();
    if (id == null) return;
    try {
      await ref.read(matchingRepositoryProvider).deletePreference(id);
      if (!mounted) return;
      showGxSnack(context, 'Profile removed', type: GxSnackType.success);
      _load();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      showGxSnack(context, msg ?? 'Could not delete', type: GxSnackType.error);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  Future<void> _setOpenToWork(bool open) async {
    try {
      await ref.read(talentRepositoryProvider).updateProfile({
        'profileStatus': open ? 'ACTIVE' : 'PAUSED',
      });
      await _load();
      if (!mounted) return;
      showGxSnack(
        context,
        open
            ? 'You are open to work — all active profiles can match'
            : 'Open to work is off — no profiles will match until you turn it back on',
        type: GxSnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Could not update profile: $e',
          type: GxSnackType.error);
    }
  }

  Future<void> _setPreferencePaused(
      Map<String, dynamic> pref, bool paused) async {
    final id = pref['id']?.toString();
    if (id == null || _updatingPreferences.contains(id)) return;
    setState(() => _updatingPreferences.add(id));
    try {
      await ref.read(matchingRepositoryProvider).updatePreference(id, {
        'matchingPaused': paused,
      });
      if (!mounted) return;
      setState(() {
        for (final profile in _prefs) {
          if (profile['id']?.toString() == id) {
            profile['matchingPaused'] = paused;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Could not update profile: $e',
          type: GxSnackType.error);
    } finally {
      if (mounted) setState(() => _updatingPreferences.remove(id));
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> pref) async {
    final days = _daysUntilDeletable(pref);
    if (days > 0) {
      showGxSnack(
        context,
        'Profiles can be deleted $days day${days == 1 ? '' : 's'} after creation (anti-spam rule).',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this profile?'),
        content: Text(
          'Remove "${pref['jobType']}" from your account? This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _delete(pref);
  }

  int get _strength {
    final talent = _talent;
    if (talent == null) return 0;
    var filled = 0;
    const total = 8;
    if (_stringsOf(talent['preferredRoles']).isNotEmpty) filled++;
    if (_stringsOf(talent['employmentTypes']).isNotEmpty || _prefs.isNotEmpty) {
      filled++;
    }
    if (_stringsOf(talent['skills']).isNotEmpty) filled++;
    if ((talent['experience']?.toString() ?? '').isNotEmpty) filled++;
    if (talent['expectedSalary'] != null) filled++;
    if (talent['lat'] != null && talent['lng'] != null) filled++;
    if ((talent['travelRadiusKm'] as num?) != null) filled++;
    if ((talent['availability']?.toString() ?? '').isNotEmpty) filled++;
    return ((filled / total) * 100).round();
  }

  List<String> _stringsOf(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  int _daysUntilDeletable(Map<String, dynamic> pref) {
    final created = DateTime.tryParse(pref['createdAt']?.toString() ?? '');
    if (created == null) return 7;
    final unlock = created.add(const Duration(days: 7));
    final left = unlock.difference(DateTime.now()).inDays;
    return left < 0 ? 0 : left + (unlock.isAfter(DateTime.now()) ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final catalog =
        ref.watch(hiringCatalogProvider).value ?? HiringCatalog.fallback;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Job Profiles',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.gx.ink,
                    ),
                  ),
                ),
                Text(
                  '$_freeProfiles/2 free',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.gx.ink.withValues(alpha: 0.5),
                  ),
                ),
                IconButton(
                  tooltip: 'Career plans',
                  icon: const Icon(Icons.workspace_premium_outlined),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute<void>(
                      builder: (_) => const PlatformPlansScreen(family: 'CAREER'),
                    ));
                    if (mounted) await _load();
                  },
                ),
                IconButton(
                    tooltip: 'Pending payments',
                    icon: const Icon(Icons.receipt_long),
                    onPressed: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PendingPaymentsScreen()));
                      if (mounted) _load();
                    }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Create different profiles for different kinds of work.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: context.gx.ink.withValues(alpha: 0.55),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_talent != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Open to work'),
                subtitle: Text(
                  _talent?['profileStatus'] == 'PAUSED'
                      ? 'Off — employers cannot match any of your profiles'
                      : 'On — active profiles can receive matches and invites',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.gx.ink.withValues(alpha: 0.55),
                  ),
                ),
                value: _talent?['profileStatus'] != 'PAUSED',
                activeThumbColor: GixbeeTheme.accentGreen,
                onChanged: _setOpenToWork,
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _prefs.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              GxEmptyState(
                                icon: Icons.badge_outlined,
                                title: 'No job profile yet',
                                message:
                                    'Create a profile so Gixbee can match you with suitable jobs.',
                                actionLabel: 'Create Profile',
                                onAction: () => _openForm(),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: _prefs.length,
                            itemBuilder: (_, i) {
                              final p = _prefs[i];
                              final details = p['seekerDetails'] as Map? ?? {};
                              final locations =
                                  (details['locations'] as List? ?? [])
                                      .whereType<Map>()
                                      .map((row) => row['label'])
                                      .whereType<String>()
                                      .toList();
                              final days = _daysUntilDeletable(p);
                              final prefPaused = p['matchingPaused'] == true;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Material(
                                  color: context.gx.card,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _openForm(existing: p),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${details['profileName'] ?? p['jobType'] ?? ''}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                    color: context.gx.ink,
                                                  ),
                                                ),
                                              ),
                                              if (prefPaused)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: context.gx.ink
                                                        .withValues(
                                                            alpha: 0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Text(
                                                    'PAUSED',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: context.gx.ink
                                                          .withValues(
                                                              alpha: 0.55),
                                                    ),
                                                  ),
                                                ),
                                              if (p['requiresCareerPlan'] == true)
                                            Text(p['careerPlanUntil'] == null
                                                ? 'Pro expired · renew to resume matching'
                                                : 'Pro access until ${eventDate(p['careerPlanUntil'])}'),
                                          if (p['isPaid'] == true)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: GixbeeTheme
                                                        .accentGreen
                                                        .withValues(
                                                            alpha: 0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: const Text(
                                                    'PAID',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: GixbeeTheme
                                                          .accentGreen,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          SwitchListTile(
                                            key: ValueKey(
                                                'job-profile-switch-${p['id']}'),
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(prefPaused
                                                ? 'Matching off'
                                                : 'Matching on'),
                                            subtitle: _talent?[
                                                            'profileStatus'] ==
                                                        'PAUSED' &&
                                                    !prefPaused
                                                ? const Text(
                                                    'Turn on Open to work to receive matches')
                                                : null,
                                            value: !prefPaused,
                                            activeThumbColor:
                                                GixbeeTheme.accentPurple,
                                            onChanged:
                                                _updatingPreferences.contains(
                                                        p['id']?.toString())
                                                    ? null
                                                    : (enabled) =>
                                                        _setPreferencePaused(
                                                            p, !enabled),
                                          ),
                                          const SizedBox(height: 6),
                                          if (p['isPaid'] == true)
                                            Text(
                                                '${DateTime.tryParse('${p['paidUntil']}')?.isAfter(DateTime.now()) == true ? 'Active until' : 'Matching paused · expired'} ${eventDate(p['paidUntil'])}. Tap to renew.'),
                                          Text(
                                            'Profile strength $_strength%',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: context.gxSuccessInk,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            [
                                              if (details['profileName'] !=
                                                  null)
                                                '${p['jobType']}',
                                              if (p['employmentType'] != null)
                                                catalog.labelForCode(
                                                    p['employmentType']
                                                        ?.toString()),
                                              if (locations.isNotEmpty)
                                                locations
                                                    .asMap()
                                                    .entries
                                                    .map((entry) =>
                                                        '${entry.key + 1}. ${entry.value}')
                                                    .join(' → ')
                                              else if ((p['preferredLocation'] ??
                                                      '')
                                                  .toString()
                                                  .isNotEmpty)
                                                '${p['preferredLocation']}',
                                              if (p['expectedSalary'] != null)
                                                '₹${p['expectedSalary']} ${p['expectedSalaryPeriod'] ?? 'MONTHLY'}${p['salaryNegotiable'] == true ? ' negotiable' : ''}',
                                              if (p['noticePeriod'] ==
                                                      'CUSTOM_DATE' &&
                                                  details['availableOn'] !=
                                                      null)
                                                'Joining ${details['availableOn']}'
                                              else
                                                '${p['noticePeriod'] ?? 'IMMEDIATE'}',
                                            ]
                                                .where((s) => s.isNotEmpty)
                                                .join(' · '),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.gx.ink
                                                  .withValues(alpha: 0.55),
                                            ),
                                          ),
                                          if ((p['skills'] as List?)
                                                  ?.isNotEmpty ==
                                              true) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                for (final s
                                                    in (p['skills'] as List)
                                                        .take(6))
                                                  Chip(
                                                    label: Text('$s'),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 4,
                                            runSpacing: 0,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              TextButton(
                                                onPressed: () =>
                                                    _openForm(existing: p),
                                                child: const Text('Edit'),
                                              ),
                                              TextButton.icon(
                                                onPressed: () =>
                                                    _confirmDelete(p),
                                                icon: Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: days > 0
                                                      ? context.gx.ink
                                                          .withValues(
                                                              alpha: 0.35)
                                                      : Colors.red.shade700,
                                                ),
                                                label: Text(
                                                  days > 0
                                                      ? 'Delete ($days d)'
                                                      : 'Delete',
                                                  style: TextStyle(
                                                    color: days > 0
                                                        ? context.gx.ink
                                                            .withValues(
                                                                alpha: 0.45)
                                                        : Colors.red.shade700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (days > 0)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Delete unlocks $days day${days == 1 ? '' : 's'} after this profile was created.',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: context.gx.ink
                                                      .withValues(alpha: 0.45),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: GxButton(
              label: '+ Add another job profile',
              accent: GixbeeTheme.accentGreen,
              onTap: () => _openForm(),
            ),
          ),
        ],
      ),
    );
  }
}
