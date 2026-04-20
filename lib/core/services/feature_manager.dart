class FeatureManager {
  final List<String> features;

  FeatureManager(this.features);

  bool hasFeature(String feature) {
    return features.contains(feature);
  }
}