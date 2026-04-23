import '../shared/models/worker.dart';

class MockRepository {
  static List<Worker> getWorkers() {
    return [
      Worker(
        id: '1',
        name: 'Elena Rodriguez',
        title: 'Master Electrician',
        bio:
            'Certified industrial and residential electrician with 10+ years of experience. Specialist in smart home installations.',
        imageUrl: 'https://i.pravatar.cc/150?u=1',
        rating: 4.9,
        completedJobs: 142,
        reviewCount: 89,
        isFeatured: true,
        hourlyRate: 45.0,
        skills: ['Wiring', 'Smart Home', 'Troubleshooting', 'Solar'],
        availabilityTags: ['Instant', 'Weekend'],
        primaryType: SkillType.manual,
        status: 'available',
      ),
      Worker(
        id: '2',
        name: 'David Chen',
        title: 'React Native Developer',
        bio:
            'Full-stack developer focused on mobile experiences. Former lead at TechFlow.',
        imageUrl: 'https://i.pravatar.cc/150?u=2',
        rating: 5.0,
        completedJobs: 38,
        reviewCount: 32,
        isFeatured: false,
        hourlyRate: 80.0,
        skills: ['Flutter', 'React', 'Node.js', 'Firebase'],
        availabilityTags: ['Evening', 'Remote'],
        primaryType: SkillType.digital,
        status: 'available',
      ),
      Worker(
        id: '3',
        name: 'Sarah Johnson',
        title: 'Certified Caregiver',
        bio:
            'Compassionate care for elderly and special needs patients. BLS certified.',
        imageUrl: 'https://i.pravatar.cc/150?u=3',
        rating: 4.8,
        completedJobs: 215,
        reviewCount: 194,
        isFeatured: true,
        hourlyRate: 30.0,
        skills: ['Elderly Care', 'First Aid', 'Companionship'],
        availabilityTags: ['24/7', 'Certified'],
        primaryType: SkillType.care,
        status: 'available',
      ),
    ];
  }
}
