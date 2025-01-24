import "dart:async";

import "package:flutter/foundation.dart" show kDebugMode;
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import "package:ml_linalg/linalg.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/extensions/stop_watch.dart";
import "package:photos/generated/protos/ente/common/vector.pb.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_indexing_isolate.dart";
import 'package:photos/services/machine_learning/ml_service.dart';
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/services/user_remote_flag_service.dart";
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/captioned_text_widget.dart';
import 'package:photos/ui/components/expandable_menu_item_widget.dart';
import 'package:photos/ui/components/menu_item_widget/menu_item_widget.dart';
import "package:photos/ui/components/toggle_switch_widget.dart";
import 'package:photos/ui/settings/common_settings.dart';
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/ml_util.dart";
import 'package:photos/utils/toast_util.dart';

class MLDebugSectionWidget extends StatefulWidget {
  const MLDebugSectionWidget({super.key});

  @override
  State<MLDebugSectionWidget> createState() => _MLDebugSectionWidgetState();
}

class _MLDebugSectionWidgetState extends State<MLDebugSectionWidget> {
  Timer? _timer;
  bool isExpanded = false;
  final Logger logger = Logger("MLDebugSectionWidget");
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (isExpanded) {
        setState(() {
          // Your state update logic here
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExpandableMenuItemWidget(
      title: "ML Debug",
      selectionOptionsWidget: _getSectionOptions(context),
      leadingIcon: Icons.bug_report_outlined,
      onExpand: (p0) => isExpanded = p0,
    );
  }

  Widget _getSectionOptions(BuildContext context) {
    logger.info("Building ML Debug section options");
    return Column(
      children: [
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "(Re)fill up vector DB",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            try {
              final w = (kDebugMode ? EnteWatch('MLDataDB') : null)?..start();
              final allFaces = await MLDataDB.instance.getAllFaces();
              w?.log('get all faces for ${allFaces.length} faces');
              await MLDataDB.instance.cleanVectorDB();
              w?.log('cleaning vector db');
              await MLDataDB.instance
                  .bulkInsertFacesInVectorDbUltraLight(allFaces);
              w?.log('inserting ${allFaces.length} faces into the vector db');
            } catch (e, s) {
              logger.warning('vector DB fill failed ', e, s);
              await showGenericErrorDialog(context: context, error: e);
            }
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Search vector DB",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            try {
              final w = (kDebugMode ? EnteWatch('MLDataDB') : null)?..start();
              final persons = await PersonService.instance.getPersons();
              w?.log('get all persons for ${persons.length} persons');
              String laurensID = '';
              for (final person in persons) {
                if (person.data.name.toLowerCase().contains('laurens')) {
                  laurensID = person.remoteID;
                }
              }
              if (laurensID.isEmpty) {
                throw Exception('Laurens not found');
              }
              final laurensFaceIDs =
                  await MLDataDB.instance.getFaceIDsForPerson(laurensID);
              w?.log(
                'getting all face ids for laurens (${laurensFaceIDs.length} faces)',
              );
              final laurensFaceIdToEmbeddingData = await MLDataDB.instance
                  .getFaceEmbeddingMapForFaces(laurensFaceIDs);
              final laurensFaceIdToEmbedding = laurensFaceIdToEmbeddingData.map(
                (key, value) => MapEntry(key, EVector.fromBuffer(value).values),
              );
              final facesCount = laurensFaceIdToEmbedding.length;
              int closestFoundFaceIsLaurens = 0;
              int embedddingsTested = 0;
              for (final faceIdEmbedding in laurensFaceIdToEmbedding.entries) {
                // final faceId = faceIdEmbedding.key;
                final embedding = faceIdEmbedding.value;
                final similarFaceID = await MLDataDB.instance
                    .getClosestFaceIdsFromVectorDB(embedding);
                if (similarFaceID.isNotEmpty) {
                  // final closestFace = similarFaces.first;
                  if (laurensFaceIDs.contains(similarFaceID)) {
                    closestFoundFaceIsLaurens++;
                  }
                }
                embedddingsTested++;
                w?.log('$embedddingsTested / $facesCount embeddings tested');
              }
              w?.log(
                'finding similar faces for $facesCount faces, with success rate ${closestFoundFaceIsLaurens / facesCount}',
              );
            } catch (e, s) {
              logger.warning('vector DB search failed ', e, s);
              await showGenericErrorDialog(context: context, error: e);
            }
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Benchmark Vector DB",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            try {
              final w = (kDebugMode ? EnteWatch('MLDataDB') : null)?..start();
              final persons = await PersonService.instance.getPersons();
              w?.log('get all persons for ${persons.length} persons');
              String laurensID = '';
              for (final person in persons) {
                if (person.data.name.toLowerCase().contains('laurens')) {
                  laurensID = person.remoteID;
                }
              }
              if (laurensID.isEmpty) {
                throw Exception('Laurens not found');
              }
              final laurensFaceIDs =
                  await MLDataDB.instance.getFaceIDsForPerson(laurensID);
              w?.log(
                'getting all face ids for laurens (${laurensFaceIDs.length} faces)',
              );
              final laurensFaceIdToEmbeddingData = await MLDataDB.instance
                  .getFaceEmbeddingMapForFaces(laurensFaceIDs);
              final laurensFaceIdToEmbedding = laurensFaceIdToEmbeddingData.map(
                (key, value) => MapEntry(key, EVector.fromBuffer(value).values),
              );
              final facesCount = laurensFaceIdToEmbedding.length;
              final allFaces = await MLDataDB.instance.getAllFaces();

              // Benchmarking the vector DB
              int embeddingsTested = 0;
              w?.reset();
              for (final faceIdEmbedding in laurensFaceIdToEmbedding.entries) {
                // final faceId = faceIdEmbedding.key;
                final embedding = faceIdEmbedding.value;
                final similarFaceID = await MLDataDB.instance
                    .getClosestFaceIdsFromVectorDB(embedding);
                embeddingsTested++;
                if (embeddingsTested % 1000 == 0) {
                  w?.log(
                    '$embeddingsTested / $facesCount embeddings tested in vector DB',
                  );
                }
              }
              w?.log(
                'Done with ${allFaces.length * facesCount} (${allFaces.length} x $facesCount}) embeddings comparisons in vector DB',
              );

              // Benchmarking our own vector comparisons
              final allVectors = allFaces.map((face) {
                final eVector = Vector.fromList(face.embedding);
                return eVector;
              }).toList();
              final laurensFaceIdToEmbeddingVectors = laurensFaceIdToEmbedding
                  .map((key, value) => MapEntry(key, Vector.fromList(value)));
              embeddingsTested = 0;
              w?.reset();
              for (final faceIdVector
                  in laurensFaceIdToEmbeddingVectors.entries) {
                // final faceId = faceIdEmbedding.key;
                final vector = faceIdVector.value;
                for (final otherVector in allVectors) {
                  final distance = 1 - vector.dot(otherVector);
                }
                embeddingsTested++;
                if (embeddingsTested % 1000 == 0) {
                  w?.log(
                    '$embeddingsTested / $facesCount embeddings tested with own vectors',
                  );
                }
              }
              w?.log(
                'Done with ${allFaces.length * facesCount} (${allFaces.length} x $facesCount}) embeddings comparisons in own method',
              );
            } catch (e, s) {
              logger.warning('vector DB search failed ', e, s);
              await showGenericErrorDialog(context: context, error: e);
            }
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: FutureBuilder<IndexStatus>(
            future: getIndexStatus(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final IndexStatus status = snapshot.data!;
                return CaptionedTextWidget(
                  title: "ML (${status.indexedItems} indexed)",
                );
              }
              return const SizedBox.shrink();
            },
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => userRemoteFlagService
                .getCachedBoolValue(UserRemoteFlagService.mlEnabled),
            onChanged: () async {
              try {
                final oldMlConsent = userRemoteFlagService
                    .getCachedBoolValue(UserRemoteFlagService.mlEnabled);
                final mlConsent = !oldMlConsent;
                await userRemoteFlagService.setBoolValue(
                  UserRemoteFlagService.mlEnabled,
                  mlConsent,
                );
                logger.info('ML consent turned ${mlConsent ? 'on' : 'off'}');
                if (!mlConsent) {
                  MLService.instance.pauseIndexingAndClustering();
                  unawaited(
                    MLIndexingIsolate.instance.cleanupLocalIndexingModels(),
                  );
                } else {
                  await MLService.instance.init();
                  await SemanticSearchService.instance.init();
                  unawaited(MLService.instance.runAllML(force: true));
                }
                if (mounted) {
                  setState(() {});
                }
              } catch (e, s) {
                logger.warning('indexing failed ', e, s);
                await showGenericErrorDialog(context: context, error: e);
              }
            },
          ),
          singleBorderRadius: 8,
          isGestureDetectorDisabled: true,
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Remote fetch",
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => localSettings.remoteFetchEnabled,
            onChanged: () async {
              try {
                await localSettings.toggleRemoteFetch();
                logger.info(
                  'Remote fetch is turned ${localSettings.remoteFetchEnabled ? 'on' : 'off'}',
                );
                if (mounted) {
                  setState(() {});
                }
              } catch (e, s) {
                logger.warning(
                  'Remote fetch toggle failed ',
                  e,
                  s,
                );
                await showGenericErrorDialog(
                  context: context,
                  error: e,
                );
              }
            },
          ),
          singleBorderRadius: 8,
          isGestureDetectorDisabled: true,
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Local indexing",
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => localSettings.isMLLocalIndexingEnabled,
            onChanged: () async {
              final localIndexing = await localSettings.toggleLocalMLIndexing();
              if (localIndexing) {
                unawaited(MLService.instance.runAllML(force: true));
              } else {
                MLService.instance.pauseIndexingAndClustering();
                unawaited(
                  MLIndexingIsolate.instance.cleanupLocalIndexingModels(),
                );
              }

              if (mounted) {
                setState(() {});
              }
            },
          ),
          singleBorderRadius: 8,
          isGestureDetectorDisabled: true,
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Auto indexing",
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => !MLService.instance.debugIndexingDisabled,
            onChanged: () async {
              try {
                MLService.instance.debugIndexingDisabled =
                    !MLService.instance.debugIndexingDisabled;
                if (MLService.instance.debugIndexingDisabled) {
                  MLService.instance.pauseIndexingAndClustering();
                } else {
                  unawaited(MLService.instance.runAllML());
                }
                if (mounted) {
                  setState(() {});
                }
              } catch (e, s) {
                logger.warning('debugIndexingDisabled toggle failed ', e, s);
                await showGenericErrorDialog(context: context, error: e);
              }
            },
          ),
          singleBorderRadius: 8,
          isGestureDetectorDisabled: true,
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Trigger run ML",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            try {
              MLService.instance.debugIndexingDisabled = false;
              unawaited(MLService.instance.runAllML());
            } catch (e, s) {
              logger.warning('indexAndClusterAll failed ', e, s);
              await showGenericErrorDialog(context: context, error: e);
            }
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Trigger run indexing",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            try {
              MLService.instance.debugIndexingDisabled = false;
              unawaited(MLService.instance.fetchAndIndexAllImages());
            } catch (e, s) {
              logger.warning('indexing failed ', e, s);
              await showGenericErrorDialog(context: context, error: e);
            }
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: FutureBuilder<double>(
            future: MLDataDB.instance.getClusteredToIndexableFilesRatio(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return CaptionedTextWidget(
                  title:
                      "Trigger clustering (${(100 * snapshot.data!).toStringAsFixed(0)}% done)",
                );
              }
              return const SizedBox.shrink();
            },
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            try {
              await PersonService.instance.fetchRemoteClusterFeedback();
              MLService.instance.debugIndexingDisabled = false;
              await MLService.instance.clusterAllImages();
              Bus.instance.fire(PeopleChangedEvent());
              showShortToast(context, "Done");
            } catch (e, s) {
              logger.warning('clustering failed ', e, s);
              await showGenericErrorDialog(context: context, error: e);
            }
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Update discover",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            try {
              await magicCacheService.updateCache(forced: true);
            } catch (e, s) {
              logger.warning('Update discover failed', e, s);
              await showGenericErrorDialog(context: context, error: e);
            }
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Sync person mappings ",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            try {
              await faceRecognitionService.syncPersonFeedback();
              showShortToast(context, "Done");
            } catch (e, s) {
              logger.warning('sync person mappings failed ', e, s);
              await showGenericErrorDialog(context: context, error: e);
            }
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Show empty indexes",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            final emptyFaces = await MLDataDB.instance.getErroredFaceCount();
            showShortToast(context, '$emptyFaces empty faces');
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Reset faces feedback",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          alwaysShowSuccessState: true,
          onTap: () async {
            await showChoiceDialog(
              context,
              title: "Are you sure?",
              body:
                  "This will drop all people and their related feedback stored locally. It will keep clustering labels and embeddings untouched, as well as persons stored on remote.",
              firstButtonLabel: "Yes, confirm",
              firstButtonOnTap: () async {
                try {
                  await MLDataDB.instance.dropFacesFeedbackTables();
                  Bus.instance.fire(PeopleChangedEvent());
                  showShortToast(context, "Done");
                } catch (e, s) {
                  logger.warning('reset feedback failed ', e, s);
                  await showGenericErrorDialog(context: context, error: e);
                }
              },
            );
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Reset faces feedback and clustering",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            await showChoiceDialog(
              context,
              title: "Are you sure?",
              body:
                  "This will delete all people (also from remote), their related feedback and clustering labels. It will keep embeddings untouched.",
              firstButtonLabel: "Yes, confirm",
              firstButtonOnTap: () async {
                try {
                  final List<PersonEntity> persons =
                      await PersonService.instance.getPersons();
                  for (final PersonEntity p in persons) {
                    await PersonService.instance.deletePerson(p.remoteID);
                  }
                  await MLDataDB.instance.dropClustersAndPersonTable();
                  Bus.instance.fire(PeopleChangedEvent());
                  showShortToast(context, "Done");
                } catch (e, s) {
                  logger.warning('peopleToPersonMapping remove failed ', e, s);
                  await showGenericErrorDialog(context: context, error: e);
                }
              },
            );
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Reset all local faces",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            await showChoiceDialog(
              context,
              title: "Are you sure?",
              body:
                  "This will drop all local faces data. You will need to again re-index faces.",
              firstButtonLabel: "Yes, confirm",
              firstButtonOnTap: () async {
                try {
                  await MLDataDB.instance
                      .dropClustersAndPersonTable(faces: true);
                  Bus.instance.fire(PeopleChangedEvent());
                  showShortToast(context, "Done");
                } catch (e, s) {
                  logger.warning('drop feedback failed ', e, s);
                  await showGenericErrorDialog(context: context, error: e);
                }
              },
            );
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: const CaptionedTextWidget(
            title: "Reset all local clip",
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            await showChoiceDialog(
              context,
              title: "Are you sure?",
              body:
                  "You will need to again re-index or fetch all clip image embeddings.",
              firstButtonLabel: "Yes, confirm",
              firstButtonOnTap: () async {
                try {
                  await SemanticSearchService.instance.clearIndexes();
                  showShortToast(context, "Done");
                } catch (e, s) {
                  logger.warning('drop clip embeddings failed ', e, s);
                  await showGenericErrorDialog(context: context, error: e);
                }
              },
            );
          },
        ),
      ],
    );
  }
}
