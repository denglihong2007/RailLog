import 'package:flutter/material.dart';
import 'package:raillog/src/pages/entity_detail_page.dart';
import 'package:raillog/src/services/entity_review_service.dart';

void openEntityReviewTarget(BuildContext context, EntityReview review) {
  final type = _entityTypeForReview(review);
  if (type == null || review.entityKey.trim().isEmpty) return;
  openEntityPage(context, type, review.entityKey);
}

EntityType? _entityTypeForReview(EntityReview review) {
  final entityType = review.entityType.trim().toLowerCase();
  return switch (entityType) {
    'station' => EntityType.station,
    'route' => EntityType.route,
    'company' => EntityType.company,
    'rollingstock' => EntityType.rollingStock,
    'train' => EntityType.train,
    _ => switch (review.reviewType) {
      'station' || 'transfer' => EntityType.station,
      'route' => EntityType.route,
      'company' || 'meal' => EntityType.company,
      'rollingstock' => EntityType.rollingStock,
      'train' => EntityType.train,
      _ => null,
    },
  };
}
