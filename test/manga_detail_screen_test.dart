import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/screens/manga_detail_screen.dart';
import 'package:kuro_reader/services/download_manager.dart';
import 'package:kuro_reader/services/storage_service.dart';

import 'support/network_image_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  final dummyCoverBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAgCAIAAACU62+bAAAAHElEQVR4nGN4KOtBEmIY1TCqYVTDqIZRDSNBAwBtMowfZv2fjwAAAABJRU5ErkJggg==',
  );

  List<Chapter> makeChapters({
    required int count,
    String prefix = 'ch',
    MangaSourceType source = MangaSourceType.mangadex,
    List<String> languages = const ['PT-BR', 'EN'],
  }) {
    return [
      for (var i = count; i >= 1; i--)
        Chapter(
          id: '${prefix}_$i',
          source: source,
          chapterNumber: '$i',
          title: 'Capítulo Especial Número $i com Título Longo',
          language: languages[i % languages.length],
          pages: 18 + (i % 10),
          scanlator: 'Scan YOMI',
        ),
    ];
  }

  Manga buildSampleManga({
    String id = 'manga-detail-1',
    String title = 'Kaguya-sama: Love Is War',
    String description =
        'Synopsis in English used when there is no Portuguese description available.',
    Map<String, String> localizedDescriptions = const {
      'pt-br':
          'Em uma prestigiada academia, dois gênios orgulhosos travam uma batalha psicológica diária para fazer o outro declarar seus sentimentos primeiro, enquanto vivem momentos cômicos no conselho estudantil ao longo de dezenas de capítulos memoráveis.',
      'en':
          'At a prestigious academy, two proud geniuses wage a daily psychological battle to make the other confess first during chaotic student council days full of schemes and hilarious misunderstandings.',
    },
    List<String> tags = const [
      'Comédia Romântica',
      'Seinen',
      'Psicológico',
      'Vida Escolar',
      'Premiado',
      'Anime',
    ],
    List<Manga> alternativeSources = const [],
  }) {
    return Manga(
      id: id,
      source: MangaSourceType.mangadex,
      title: title,
      description: description,
      localizedDescriptions: localizedDescriptions,
      status: 'ONGOING',
      directCoverUrl: 'https://example.com/0.png',
      directHighResCoverUrl: 'https://example.com/0.png',
      tags: tags,
      alternativeSources: alternativeSources,
    );
  }

  void setViewport(
    WidgetTester tester, {
    required double width,
    double height = 820,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget wrapApp(
    Widget child, {
    double textScale = 1.0,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: padding,
        ),
        child: widget!,
      ),
      home: child,
    );
  }

  Future<void> pumpSettledReal(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> withMockNetworkImages(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugNetworkImageHttpClientProvider =
        () => FixtureImageClient([dummyCoverBytes]);
    try {
      await body();
    } finally {
      await tester.pumpWidget(const SizedBox());
      debugNetworkImageHttpClientProvider = null;
    }
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('yomi_detail_test_');
    Hive.init(tempDir.path);
    for (final boxName in [
      StorageService.favBoxName,
      StorageService.historyBoxName,
      StorageService.settingsBoxName,
      StorageService.downloadsBoxName,
    ]) {
      await Hive.openBox(boxName);
    }
    DownloadManager.activeMangaDownloads.value = {};
  });

  tearDown(() async {
    DownloadManager.activeMangaDownloads.value = {};
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Modelo Manga — Sinopse localizada sem mutação', () {
    test('Manga.fromJson preserva PT-BR e EN e serializa sem perder idiomas', () {
      final parsed = Manga.fromJson({
        'id': 'mdx-synopsis-1',
        'attributes': {
          'title': {'en': 'Example Work'},
          'description': {
            'pt-br': 'Sinopse oficial em português brasileiro.',
            'en': 'Official English synopsis text.',
          },
          'contentRating': 'safe',
          'tags': [],
        },
      });

      expect(parsed.description, 'Sinopse oficial em português brasileiro.');
      expect(
        parsed.portugueseDescription,
        'Sinopse oficial em português brasileiro.',
      );
      expect(
        parsed.originalLanguageDescription,
        'Official English synopsis text.',
      );
      expect(parsed.hasAlternativeOriginalDescription, isTrue);

      final roundTripped = Manga.fromMap(parsed.toMap());
      expect(
        roundTripped.localizedDescriptions,
        equals(parsed.localizedDescriptions),
      );
      expect(roundTripped.preferredDescription, parsed.preferredDescription);
      expect(
        roundTripped.originalLanguageDescription,
        parsed.originalLanguageDescription,
      );
    });

    test('Obra em inglês usa sinopse PT de fonte alternativa preservando original', () {
      final altMdx = Manga(
        id: 'mdx-alt',
        source: MangaSourceType.mangadex,
        title: 'Horizonte',
        description: 'Versão em português.',
        localizedDescriptions: const {
          'pt-br': 'Versão em português.',
          'en': 'English fallback.',
        },
        status: 'ONGOING',
        tags: const [],
      );
      final aniMain = Manga(
        id: 'ani_title_Horizonte',
        source: MangaSourceType.anilist,
        title: 'Horizonte',
        description: 'Original AniList English summary.',
        status: 'RELEASING',
        tags: const [],
        alternativeSources: [altMdx],
      );

      expect(aniMain.preferredDescription, 'Versão em português.');
      expect(
        aniMain.originalLanguageDescription,
        'Original AniList English summary.',
      );
      expect(aniMain.description, 'Original AniList English summary.');
    });
  });

  group('Responsividade em larguras Android e orientação horizontal', () {
    for (final width in [320.0, 360.0, 393.0, 412.0, 480.0]) {
      testWidgets(
        'renderiza sem overflow, cabeçalho de 2 linhas e botões alinhados em ${width.toInt()}dp',
        (tester) async {
          await withMockNetworkImages(tester, () async {
            setViewport(tester, width: width, height: 840);
            final mdxChapters = makeChapters(count: 203, prefix: 'mdx');
            final aniChapters = makeChapters(
              count: 42,
              prefix: 'ani',
              source: MangaSourceType.anilist,
            );

            await tester.pumpWidget(
              wrapApp(
                MangaDetailScreen(
                  key: ValueKey('detail_$width'),
                  manga: buildSampleManga(
                    title:
                        'Título Muito Longo Para Testar Quebra Segura Sem Cortes Na Tela De Detalhes Em Celulares Pequenos',
                  ),
                  heroTag: 'hero_$width',
                  sourceDiscoveryLoader: (manga, {offset = 0}) async => {
                    MangaSourceType.mangadex: mdxChapters,
                    MangaSourceType.anilist: aniChapters,
                  },
                ),
                padding: const EdgeInsets.fromLTRB(0, 36, 0, 24),
              ),
            );
            await pumpSettledReal(tester);

            expect(tester.takeException(), isNull);

            // Verifica chips de gênero com altura uniforme e sem overflow
            final seinenFinder = find.text('Seinen');
            final animeFinder = find.text('Anime');
            await tester.ensureVisible(animeFinder);
            await tester.pumpAndSettle();
            final seinenChip = tester.getRect(
              find
                  .ancestor(of: seinenFinder, matching: find.byType(Container))
                  .first,
            );
            final animeChip = tester.getRect(
              find
                  .ancestor(of: animeFinder, matching: find.byType(Container))
                  .first,
            );
            expect((seinenChip.height - animeChip.height).abs(), lessThan(1));

            // Cabeçalho da lista de capítulos em 2 linhas independentes
            final titleFinder = find.text('Capítulos (203)');
            final sortFinder = find.byIcon(Icons.arrow_downward_rounded);
            final todosFinder = find.text('Todos');
            final ptFinder = find.text('PT');
            final enFinder = find.text('EN');
            final esFinder = find.text('ES');

            await tester.ensureVisible(todosFinder);
            await tester.pumpAndSettle();

            expect(titleFinder, findsOneWidget);
            expect(sortFinder, findsOneWidget);
            expect(todosFinder, findsOneWidget);
            expect(ptFinder, findsOneWidget);
            expect(enFinder, findsOneWidget);
            expect(esFinder, findsOneWidget);

            final titleRect = tester.getRect(titleFinder);
            final sortRect = tester.getRect(sortFinder);
            final todosRect = tester.getRect(todosFinder);
            final ptRect = tester.getRect(ptFinder);
            final enRect = tester.getRect(enFinder);
            final esRect = tester.getRect(esFinder);

            // Em larguras >= 360dp (mesmo sob fonte quadrada Ahem nos testes), fica em 1 linha;
            // em 320dp no Ahem (270dp de texto para 234dp úteis) quebra no máximo em 2 linhas sem colidir.
            expect(titleRect.height, lessThan(width >= 360 ? 34 : 56));
            expect(sortRect.left, greaterThanOrEqualTo(titleRect.right - 2));

            // Opções de idioma ficam na segunda linha, alinhadas horizontalmente
            expect(todosRect.top, greaterThanOrEqualTo(titleRect.bottom - 1));
            expect((todosRect.center.dy - ptRect.center.dy).abs(), lessThan(4));
            expect((ptRect.center.dy - enRect.center.dy).abs(), lessThan(4));
            expect((enRect.center.dy - esRect.center.dy).abs(), lessThan(4));

            // Botões principais de leitura e download possuem largura consistente
            final readBtnFinder = find.widgetWithText(
              FilledButton,
              'Começar a ler',
            );
            final downloadBtnFinder = find.widgetWithText(
              OutlinedButton,
              'Baixar mangá inteiro (203 caps)',
            );
            await tester.ensureVisible(readBtnFinder);
            await tester.pumpAndSettle();
            expect(readBtnFinder, findsOneWidget);
            expect(downloadBtnFinder, findsOneWidget);
            final readRect = tester.getRect(readBtnFinder);
            final downloadRect = tester.getRect(downloadBtnFinder);
            expect((readRect.width - downloadRect.width).abs(), lessThan(1));
            expect(readRect.right, lessThanOrEqualTo(width));

            if (width == 320) {
              await tester.pumpWidget(
                wrapApp(
                  MangaDetailScreen(
                    key: const ValueKey('detail_320_short'),
                    manga: buildSampleManga(id: 'manga-320-short'),
                    heroTag: 'hero_320_short',
                    sourceDiscoveryLoader: (manga, {offset = 0}) async => {
                      MangaSourceType.mangadex: makeChapters(
                        count: 8,
                        prefix: 's',
                      ),
                    },
                  ),
                ),
              );
              await pumpSettledReal(tester);
              final shortTitleFinder = find.text('Capítulos (8)');
              await tester.ensureVisible(shortTitleFinder);
              await tester.pumpAndSettle();
              expect(tester.getRect(shortTitleFinder).height, lessThan(34));
            }
          });
        },
      );
    }

    testWidgets(
      'adapta com texto ampliado (1.6x), 4 dígitos de capítulos, idiomas extras e paisagem sem overflow',
      (tester) async {
        await withMockNetworkImages(tester, () async {
          setViewport(tester, width: 320, height: 760);
          final chapters = [
            ...makeChapters(
              count: 1050,
              prefix: 'huge',
              languages: const ['PT-BR', 'EN', 'ES', 'FR'],
            ),
          ];

          await tester.pumpWidget(
            wrapApp(
              MangaDetailScreen(
                key: const ValueKey('detail_large_font'),
                manga: buildSampleManga(
                  title:
                      'Título Extremo Para Acessibilidade Com Fonte Ampliada Em Tela De 320dp',
                ),
                heroTag: 'hero_large_font',
                sourceDiscoveryLoader: (manga, {offset = 0}) async => {
                  MangaSourceType.mangadex: chapters,
                  MangaSourceType.anilist: chapters.take(12).toList(),
                },
              ),
              textScale: 1.6,
              padding: const EdgeInsets.fromLTRB(0, 48, 0, 34),
            ),
          );
          await pumpSettledReal(tester);

          expect(tester.takeException(), isNull);

          // Verifica que os botões superiores não colidem com o título no topo
          final backRect = tester.getRect(find.byTooltip('Voltar'));
          final heroTitleRect = tester.getRect(
            find.textContaining('Título Extremo Para Acessibilidade'),
          );
          expect(heroTitleRect.top, greaterThanOrEqualTo(backRect.bottom - 2));
          expect(heroTitleRect.right, lessThanOrEqualTo(320));

          // 4 dígitos + idioma adicional FR
          await tester.ensureVisible(find.text('Capítulos (1050)'));
          await tester.pumpAndSettle();
          expect(find.text('Capítulos (1050)'), findsOneWidget);
          expect(find.text('FR'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Agora em orientação horizontal com notch lateral (landscape 640x360)
          setViewport(tester, width: 640, height: 360);
          await tester.pumpWidget(
            wrapApp(
              MangaDetailScreen(
                key: const ValueKey('detail_landscape'),
                manga: buildSampleManga(title: 'Modo Paisagem'),
                heroTag: 'hero_landscape',
                sourceDiscoveryLoader: (manga, {offset = 0}) async => {
                  MangaSourceType.mangadex: chapters.take(25).toList(),
                },
              ),
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
            ),
          );
          await pumpSettledReal(tester);
          expect(find.text('Modo Paisagem'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      },
    );
  });

  group('Controles interativos, fontes, estados visuais e sinopse', () {
    testWidgets(
      'alterna fonte inteligente (MDX/ANI), ordenação e filtros Todos/PT/EN/ES',
      (tester) async {
        await withMockNetworkImages(tester, () async {
          setViewport(tester, width: 360, height: 820);
          final mdxChapters = [
            Chapter(
              id: 'm1',
              chapterNumber: '1',
              title: 'Primeiro PT',
              language: 'PT-BR',
              pages: 20,
            ),
            Chapter(
              id: 'm2',
              chapterNumber: '2',
              title: 'Segundo EN',
              language: 'EN',
              pages: 20,
            ),
            Chapter(
              id: 'm3',
              chapterNumber: '3',
              title: 'Terceiro ES',
              language: 'ES',
              pages: 20,
            ),
          ];
          final aniChapters = [
            Chapter(
              id: 'a1',
              source: MangaSourceType.anilist,
              chapterNumber: '1',
              title: 'Cap ANI 1',
              language: 'PT-BR',
              pages: 18,
            ),
          ];

          await tester.pumpWidget(
            wrapApp(
              MangaDetailScreen(
                key: const ValueKey('detail_controls'),
                manga: buildSampleManga(),
                heroTag: 'hero_controls',
                sourceDiscoveryLoader: (manga, {offset = 0}) async => {
                  MangaSourceType.mangadex: mdxChapters,
                  MangaSourceType.anilist: aniChapters,
                },
              ),
            ),
          );
          await pumpSettledReal(tester);

          // Auto-seleciona MDX (3 caps) com destaque 'Mais completa'
          expect(find.text('MDX: 3 caps'), findsOneWidget);
          expect(find.text('ANI: 1 caps'), findsOneWidget);
          expect(find.text('Mais completa'), findsOneWidget);
          expect(find.text('Capítulos (3)'), findsOneWidget);

          // Filtra para PT
          await tester.ensureVisible(find.text('PT'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('PT'));
          await tester.pumpAndSettle();
          expect(find.text('Capítulos (1)'), findsOneWidget);
          expect(find.textContaining('Primeiro PT'), findsOneWidget);

          // Filtra para EN
          await tester.ensureVisible(find.text('EN'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('EN'));
          await tester.pumpAndSettle();
          expect(find.text('Capítulos (1)'), findsOneWidget);
          expect(find.textContaining('Segundo EN'), findsOneWidget);

          // Filtra para ES
          await tester.ensureVisible(find.text('ES'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('ES'));
          await tester.pumpAndSettle();
          expect(find.text('Capítulos (1)'), findsOneWidget);
          expect(find.textContaining('Terceiro ES'), findsOneWidget);

          // Volta para Todos e alterna ordenação
          await tester.ensureVisible(find.text('Todos'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Todos'));
          await tester.pumpAndSettle();
          expect(find.text('Capítulos (3)'), findsOneWidget);
          expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

          await tester.ensureVisible(find.byIcon(Icons.arrow_downward_rounded));
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

          // Alterna fonte para ANI
          await tester.ensureVisible(find.text('ANI: 1 caps'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('ANI: 1 caps'));
          await tester.pumpAndSettle();
          expect(find.text('Capítulos (1)'), findsOneWidget);
          expect(find.textContaining('Cap ANI 1'), findsOneWidget);
        });
      },
    );

    testWidgets(
      'sinopse prioriza PT-BR, alterna para original sem mutar dados e expande com Ver mais / Ver menos',
      (tester) async {
        await withMockNetworkImages(tester, () async {
          setViewport(tester, width: 360, height: 820);
          final manga = buildSampleManga();

          await tester.pumpWidget(
            wrapApp(
              MangaDetailScreen(
                key: const ValueKey('detail_synopsis'),
                manga: manga,
                heroTag: 'hero_synopsis',
                sourceDiscoveryLoader: (m, {offset = 0}) async => {
                  MangaSourceType.mangadex: makeChapters(count: 2),
                },
              ),
            ),
          );
          await pumpSettledReal(tester);

          expect(find.textContaining('dois gênios orgulhosos'), findsOneWidget);
          expect(find.text('Ver original'), findsOneWidget);
          expect(find.text('Ver mais'), findsOneWidget);

          // Expande suavemente
          await tester.ensureVisible(find.text('Ver mais'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ver mais'));
          await tester.pumpAndSettle();
          expect(find.text('Ver menos'), findsOneWidget);

          // Alterna para original em inglês sem mutar o modelo original
          await tester.ensureVisible(find.text('Ver original'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ver original'));
          await tester.pumpAndSettle();
          expect(find.textContaining('two proud geniuses'), findsOneWidget);
          expect(find.text('Ver em português'), findsOneWidget);
          expect(
            manga.description,
            'Synopsis in English used when there is no Portuguese description available.',
          );

          // Retorna para português
          await tester.ensureVisible(find.text('Ver em português'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ver em português'));
          await tester.pumpAndSettle();
          expect(find.textContaining('dois gênios orgulhosos'), findsOneWidget);

          // Serviço de tradução opcional traduz sob demanda sem mutar manga.description
          final englishOnlyManga = buildSampleManga(
            id: 'manga_translate_only',
            localizedDescriptions: const {},
            description: 'English summary needing translation.',
          );
          await tester.pumpWidget(
            wrapApp(
              MangaDetailScreen(
                key: const ValueKey('detail_translator'),
                manga: englishOnlyManga,
                heroTag: 'hero_translator',
                sourceDiscoveryLoader: (m, {offset = 0}) async => {
                  MangaSourceType.mangadex: makeChapters(count: 2),
                },
                synopsisTranslator: (text) async =>
                    'Sinopse traduzida sob demanda sem alterar original.',
              ),
            ),
          );
          await pumpSettledReal(tester);
          expect(find.text('Traduzir'), findsOneWidget);
          await tester.ensureVisible(find.text('Traduzir'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Traduzir'));
          await tester.pumpAndSettle();
          expect(
            find.text('Sinopse traduzida sob demanda sem alterar original.'),
            findsOneWidget,
          );
          expect(find.text('Ver original'), findsOneWidget);
          expect(
            englishOnlyManga.description,
            'English summary needing translation.',
          );
        });
      },
    );

    testWidgets(
      'botões exibem estados de carregamento, erro com retry, download ativo, continuar capítulo e indisponibilidade',
      (tester) async {
        await withMockNetworkImages(tester, () async {
          setViewport(tester, width: 360, height: 820);

          // 1. Estado de carregamento e erro com retry
          final completer = Completer<Map<MangaSourceType, List<Chapter>>>();
          var attempts = 0;
          await tester.pumpWidget(
            wrapApp(
              MangaDetailScreen(
                key: const ValueKey('detail_loading'),
                manga: buildSampleManga(id: 'manga_loading'),
                heroTag: 'hero_loading',
                sourceDiscoveryLoader: (m, {offset = 0}) {
                  attempts++;
                  if (attempts == 1) {
                    return completer.future;
                  }
                  return Future.value({
                    MangaSourceType.mangadex: makeChapters(count: 2),
                  });
                },
              ),
            ),
          );
          await tester.pump();
          expect(find.text('Carregando capítulos...'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Conclui carregamento com erro e valida botão de tentar novamente
          completer.completeError(Exception('Sem rede'));
          await pumpSettledReal(tester);
          expect(
            find.text('Erro ao carregar — Tentar novamente'),
            findsOneWidget,
          );
          expect(find.text('Download indisponível no momento'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Toca em tentar novamente e recupera carregamento
          await tester.ensureVisible(
            find.text('Erro ao carregar — Tentar novamente'),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Erro ao carregar — Tentar novamente'));
          await pumpSettledReal(tester);
          expect(attempts, 2);
          expect(find.text('Começar a ler'), findsOneWidget);

          // 2. Estado sem capítulos (0 capítulos)
          await tester.pumpWidget(
            wrapApp(
              MangaDetailScreen(
                key: const ValueKey('detail_zero'),
                manga: buildSampleManga(id: 'manga_zero'),
                heroTag: 'hero_zero',
                sourceDiscoveryLoader: (m, {offset = 0}) async => {
                  MangaSourceType.mangadex: const <Chapter>[],
                },
              ),
            ),
          );
          await pumpSettledReal(tester);
          expect(find.text('Leitura indisponível (0 capítulos)'), findsOneWidget);
          expect(
            find.text('Download indisponível (0 capítulos)'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          // 3. Estado Continuar Cap. 1 (PT-BR) + Progresso de download em lote
          final sampleManga = buildSampleManga(id: 'manga_continue');
          final sampleChapter = Chapter(
            id: 'ch_resume_1',
            chapterNumber: '1',
            title: 'Início',
            language: 'PT-BR',
            pages: 24,
          );
          await tester.runAsync(
            () => StorageService.recordChapterOpened(sampleManga, sampleChapter),
          );

          await tester.pumpWidget(
            wrapApp(
              MangaDetailScreen(
                key: const ValueKey('detail_continue'),
                manga: sampleManga,
                heroTag: 'hero_continue',
                sourceDiscoveryLoader: (m, {offset = 0}) async => {
                  MangaSourceType.mangadex: [sampleChapter],
                },
              ),
            ),
          );
          await pumpSettledReal(tester);
          expect(find.text('Continuar Cap. 1 (PT-BR)'), findsOneWidget);

          DownloadManager.activeMangaDownloads.value = {
            sampleManga.id: (completed: 1, total: 1),
          };
          await tester.pump();
          expect(
            find.text('Baixando obra inteira: 1 de 1 capítulos...'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      },
    );
  });
}
