import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/comment_models.dart';
import '../screens/auth_screen.dart';
import '../services/cloud_auth_service.dart';

class WorkRating extends StatelessWidget {
  const WorkRating({super.key, required this.workId});
  final String workId;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  @override
  Widget build(BuildContext context) {
    final id = normalizeCommentTargetId(workId).toLowerCase();
    if (!_uuid.hasMatch(id) || !CloudAuthService.isFirebaseAvailable.value) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder(
      valueListenable: CloudAuthService.currentUser,
      builder: (context, user, _) =>
          _RatingCard(key: ValueKey((id, user?.uid)), id: id, uid: user?.uid),
    );
  }
}

class _RatingCard extends StatefulWidget {
  const _RatingCard({super.key, required this.id, required this.uid});
  final String id;
  final String? uid;
  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  late final work = FirebaseFirestore.instance
      .collection('workRatings')
      .doc(widget.id);
  late final vote = work.collection('votes').doc(widget.uid);
  late var summaries = work.snapshots();
  late var votes = widget.uid == null ? null : vote.snapshots();
  bool saving = false;
  String? message;

  Future<void> rate(int score) async {
    if (saving) return;
    if (widget.uid == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (ctx) =>
              KuroAuthScreen(onAuthenticated: () => Navigator.pop(ctx)),
        ),
      );
      return;
    }
    setState(() {
      saving = true;
      message = null;
    });
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final summary = (await tx.get(work)).data();
        final previous = (await tx.get(vote)).data()?['score'] as int?;
        final count =
            (summary?['count'] as int? ?? 0) + (previous == null ? 1 : 0);
        final total =
            (summary?['total'] as int? ?? 0) + score - (previous ?? 0);
        tx.set(vote, {
          'score': score,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(work, {
          'workId': widget.id,
          'count': count,
          'total': total,
          'rankScore': (total + 17.5) / (count + 5),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      if (mounted) setState(() => message = 'Avaliação salva.');
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              message = 'Falha ao salvar. Toque na nota para tentar novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder(
          stream: summaries,
          builder: (context, summary) {
            final data = summary.data?.data();
            final count = data?['count'] as int? ?? 0;
            final average = count == 0
                ? ''
                : ((data!['total'] as int) / count)
                      .toStringAsFixed(1)
                      .replaceAll('.', ',');
            return StreamBuilder(
              stream: votes,
              builder: (context, mine) {
                final score = mine.data?.data()?['score'] as int? ?? 0;
                final failed = summary.hasError || mine.hasError;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avaliação da comunidade',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      summary.hasError
                          ? 'Notas indisponíveis'
                          : !summary.hasData
                          ? 'Carregando notas…'
                          : count == 0
                          ? 'Seja o primeiro a avaliar'
                          : '$average / 5 · $count ${count == 1 ? "avaliação" : "avaliações"}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      children: List.generate(
                        5,
                        (i) => IconButton(
                          tooltip:
                              'Avaliar com ${i + 1} ${i == 0 ? "estrela" : "estrelas"}',
                          onPressed:
                              saving ||
                                  failed ||
                                  (widget.uid != null && !mine.hasData)
                              ? null
                              : () => rate(i + 1),
                          icon: Icon(
                            i < score
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        saving
                            ? 'Salvando…'
                            : message ??
                                  (widget.uid == null
                                      ? 'Entre para avaliar'
                                      : score == 0
                                      ? 'Toque em uma estrela para avaliar'
                                      : 'Sua nota: $score / 5'),
                      ),
                    ),
                    if (failed)
                      TextButton(
                        onPressed: () => setState(() {
                          summaries = work.snapshots();
                          votes = widget.uid == null ? null : vote.snapshots();
                        }),
                        child: const Text('Recarregar notas'),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
