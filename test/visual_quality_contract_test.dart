import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'visual scorecard preserves evidence, unknowns and no-regression gates',
    () {
      final card = jsonDecode(
        File(p.join('docs', 'visual-quality-scorecard.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(card['kind'], 'expert-heuristic-not-outcome-evidence');
      expect(card['targetPerDimension'], 4);
      final accessibilityPolicy =
          card['accessibilityReleaseBlocker'] as Map<String, dynamic>;
      expect(accessibilityPolicy['blocksRelease'], isTrue);
      expect(accessibilityPolicy['mayBeDeferredAsFollowUp'], isFalse);
      expect(
        accessibilityPolicy['primaryActionMustBeVisibleAndReachableInitially'],
        ['200_percent_text', 'short_window', 'high_dpi'],
      );
      expect(
        accessibilityPolicy['primaryActionMustPrecedeSecondaryDetailsIn'],
        ['keyboard_focus_order', 'assistive_technology_semantics'],
      );
      expect(accessibilityPolicy['minimumApplicableDimensionScore'], 4);
      expect(accessibilityPolicy['notObservedIsPass'], isFalse);
      final ids = <String>{};
      for (final surface in card['surfaces'] as List) {
        expect(ids.add(surface['id'] as String), isTrue);
        expect(surface['source'], isNotEmpty);
        expect(surface['conditions'], isNotEmpty);
        expect(surface['checks'], isNotEmpty);
        expect(
          surface['validationResult'],
          surface['current']['status'] == 'OBSERVED'
              ? 'PASS_OBSERVED_SCOPE'
              : 'NOT_OBSERVED',
          reason: '${surface['id']}: exact scoped validation result required',
        );
        if (surface['current']['status'] == 'NOT OBSERVED') {
          expect(
            surface['gate'],
            'OPEN',
            reason: '${surface['id']}: NOT_OBSERVED cannot pass release',
          );
        }
        for (final state in ['baseline', 'current']) {
          final assessment = surface[state] as Map;
          final scores = assessment['scores'];
          if (assessment['status'] == 'NOT OBSERVED') {
            expect(
              scores,
              isNull,
              reason: '${surface['id']}: unknown is not a grade',
            );
            expect(surface['gaps'], isNotEmpty);
          } else {
            expect(assessment['status'], 'OBSERVED');
            expect((scores as Map).keys.toSet(), {'D', 'H', 'G', 'A', 'T'});
            expect(assessment['evidence'], isNotEmpty);
            for (final score in scores.values) {
              expect(score, inInclusiveRange(1, 5));
              if (state == 'current' && score < card['targetPerDimension']) {
                expect(surface['gaps'], isNotEmpty);
                expect(surface['gate'], 'OPEN');
              }
            }
            for (final file in assessment['evidence'] as List) {
              expect(
                File(
                  p.join('docs', 'evidence', 'visual-quality', file as String),
                ).existsSync(),
                isTrue,
                reason: 'Missing rendered evidence for ${surface['id']}',
              );
            }
          }
        }
        final before = surface['baseline']['scores'] as Map?;
        final after = surface['current']['scores'] as Map?;
        if (before != null && after != null) {
          for (final dimension in before.keys) {
            if (after[dimension] < before[dimension]) {
              expect(
                surface['reviewedTradeoff'],
                isNotEmpty,
                reason: '${surface['id']} regressed $dimension',
              );
            }
          }
        }
      }
      expect(ids.length, greaterThanOrEqualTo(20));
    },
  );
}
