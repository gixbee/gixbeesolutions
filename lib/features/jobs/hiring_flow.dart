/// Shared recruitment pipeline labels (mirrors Rust `matching/flow.rs`).
String hiringPipelineLabel({
  required String response,
  required String decision,
  Map<String, dynamic>? progress,
}) {
  final p = progress ?? const <String, dynamic>{};
  final stage = '${p['stage'] ?? ''}';
  if (decision == 'HIRED' || stage == 'JOINED') return 'HIRED';
  if (stage == 'WITHDRAWN') return 'WITHDRAWN';
  if (decision == 'REJECTED') return 'NOT SELECTED';
  const late = {
    'INTERVIEW_PROPOSED',
    'INTERVIEW_ACCEPTED',
    'INTERVIEW_DECLINED',
    'INTERVIEW_COMPLETED',
    'OFFERED',
    'ACCEPTED',
    'OFFER_DECLINED',
    'SHORTLISTED',
  };
  if (late.contains(stage)) return stage.replaceAll('_', ' ');
  if (decision == 'SHORTLISTED') return 'SHORTLISTED';
  if (response == 'INTERESTED') return 'CHATTING';
  if (p['invited'] == true) return 'INVITED';
  if (p['viewedByEmployer'] == true || p['viewedByCandidate'] == true) {
    return 'VIEWED';
  }
  return 'PENDING';
}

bool hiringContactUnlocked({
  required String decision,
  Map<String, dynamic>? progress,
}) {
  if (decision == 'HIRED') return true;
  return progress?['contactShared'] == true;
}

bool hiringCanChat({required String response, required String decision}) {
  return response == 'INTERESTED' && decision != 'REJECTED';
}

const hiringInterviewTypeLabels = <String, String>{
  'IN_PERSON': 'In person',
  'PHONE': 'Phone',
  'VIDEO': 'Video',
};
