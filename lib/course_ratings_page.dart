import 'package:flutter/material.dart';

import 'course_catalog.dart';

class CourseRatingsPage extends StatefulWidget {
  final CourseRatingCatalog catalog;
  final CourseCatalogCourse course;
  const CourseRatingsPage({
    super.key,
    required this.catalog,
    required this.course,
  });

  @override
  State<CourseRatingsPage> createState() => _CourseRatingsPageState();
}

class _CourseRatingsPageState extends State<CourseRatingsPage> {
  late final Future<List<CourseCatalogTee>> _tees;

  @override
  void initState() {
    super.initState();
    _tees = widget.catalog.teesFor(widget.course);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Published tee ratings')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.course.name, style: Theme.of(context).textTheme.titleLarge),
        Text(
          [
            widget.course.city,
            widget.course.state,
            'USGA course ID ${widget.course.sourceId}',
          ].where((part) => part.isNotEmpty).join(' • '),
        ),
        const SizedBox(height: 8),
        Text(
          'Offline personal-use catalog with total par, course and bogey ratings, and tee slopes.'
          ' Hole-by-hole pars and yardages are not included.'
          ' Verify ratings against the current scorecard.'
          '${widget.catalog.snapshotDate == null ? '' : ' • Packaged ${widget.catalog.snapshotDate}'}',
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<CourseCatalogTee>>(
          future: _tees,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'Could not read tee ratings: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final tees = snapshot.data!;
            if (tees.isEmpty) {
              return const Text(
                'No usable tee ratings were found for this course.',
              );
            }
            return Column(
              children: [
                for (final tee in tees)
                  Card(
                    child: ListTile(
                      title: Text(tee.displayName),
                      subtitle: Text(_description(tee)),
                      isThreeLine: tee.holes == 18,
                      trailing: TextButton(
                        onPressed: () => Navigator.of(context).pop(tee),
                        child: const Text('Use tee'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  String _description(CourseCatalogTee tee) {
    final nineRatings = [
      if (tee.frontNineRating != null && tee.frontNineSlope != null)
        'Front 9 ${tee.frontNineRating!.toStringAsFixed(1)}/${tee.frontNineSlope}'
            '${tee.frontNineBogeyRating == null ? '' : ' • Bogey ${tee.frontNineBogeyRating!.toStringAsFixed(1)}'}',
      if (tee.backNineRating != null && tee.backNineSlope != null)
        'Back 9 ${tee.backNineRating!.toStringAsFixed(1)}/${tee.backNineSlope}'
            '${tee.backNineBogeyRating == null ? '' : ' • Bogey ${tee.backNineBogeyRating!.toStringAsFixed(1)}'}',
    ];
    return [
      '${tee.holes} holes • Par ${tee.par} • Rating ${tee.rating.toStringAsFixed(1)} • Slope ${tee.slope}',
      if (tee.bogeyRating != null)
        'Overall bogey rating ${tee.bogeyRating!.toStringAsFixed(1)}',
      if (nineRatings.isNotEmpty) nineRatings.join(' • '),
    ].join('\n');
  }
}
