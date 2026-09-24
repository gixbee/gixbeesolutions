import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/business/hiring_pipeline_screen.dart';
import 'package:gixbee/shared/models/job_post.dart';

void main() {
  test('job post accepts comma-separated skills and decimal salary strings', () {
    final job = JobPost.fromJson({
      'id': '1',
      'title': 'Electrician',
      'description': 'Wire a shop',
      'requiredSkills': 'Wiring, MCB',
      'salaryMin': '18000.00',
      'salaryMax': '24000.50',
      'jobType': 'Electrician',
      'experience': '1 year',
      'location': 'Kochi',
      'isActive': true,
      'employerId': 'emp',
    });
    expect(job.requiredSkills, ['Wiring', 'MCB']);
    expect(job.salaryMin, 18000);
    expect(job.salaryMax, 24000.50);
  });

  test('pipeline only offers the forward transitions the API accepts', () {
    expect(nextApplicationStages(ApplicationStatus.applied), [
      ApplicationStatus.interview,
      ApplicationStatus.rejected,
    ]);
    expect(nextApplicationStages(ApplicationStatus.interview), [
      ApplicationStatus.selected,
      ApplicationStatus.rejected,
    ]);
    expect(nextApplicationStages(ApplicationStatus.selected), isEmpty);
    expect(applicationStageLabel(ApplicationStatus.selected), 'Hired');
    expect(applicationStageLabel(ApplicationStatus.rejected), 'Not Selected');
  });
}
