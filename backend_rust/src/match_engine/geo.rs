const EARTH_KM: f64 = 6371.0;

pub fn haversine_km(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let (lat1, lng1, lat2, lng2) = (lat1.to_radians(), lng1.to_radians(), lat2.to_radians(), lng2.to_radians());
    let dlat = lat2 - lat1;
    let dlng = lng2 - lng1;
    let a = (dlat / 2.0).sin().powi(2) + lat1.cos() * lat2.cos() * (dlng / 2.0).sin().powi(2);
    EARTH_KM * 2.0 * a.sqrt().asin()
}

/// 1.0 at the pin, falling toward 0.45 at the travel radius. `None` means the
/// on-site job is outside the radius and must be excluded.
pub fn distance_feature(km: f64, radius_km: f64, remote: bool) -> Option<f32> {
    if remote {
        return Some(1.0);
    }
    if !km.is_finite() || radius_km <= 0.0 {
        return Some(0.7);
    }
    if km > radius_km {
        return None;
    }
    let t = (km / radius_km).clamp(0.0, 1.0);
    Some((1.0 - 0.55 * t) as f32)
}

/// Rough degree window so SQL can avoid a full scan before haversine.
pub fn bbox(lat: f64, lng: f64, radius_km: f64) -> (f64, f64, f64, f64) {
    let dlat = radius_km / 111.0;
    let dlng = radius_km / (111.0 * lat.to_radians().cos().abs().max(0.2));
    (lat - dlat, lat + dlat, lng - dlng, lng + dlng)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remote_ignores_distance() {
        assert_eq!(distance_feature(500.0, 10.0, true), Some(1.0));
    }

    #[test]
    fn onsite_beyond_radius_is_excluded() {
        assert_eq!(distance_feature(30.0, 10.0, false), None);
    }

    #[test]
    fn nearer_scores_higher() {
        let near = distance_feature(3.0, 25.0, false).unwrap();
        let far = distance_feature(24.0, 25.0, false).unwrap();
        assert!(near > far);
    }
}
