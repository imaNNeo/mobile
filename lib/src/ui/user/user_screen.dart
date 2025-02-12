import 'package:cached_network_image/cached_network_image.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:async/async.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'package:lichess_mobile/src/common/lichess_colors.dart';
import 'package:lichess_mobile/src/common/lichess_icons.dart';
import 'package:lichess_mobile/src/common/models.dart';
import 'package:lichess_mobile/src/common/styles.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/game/game_repository.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/ui/game/archived_game_screen.dart';
import 'package:lichess_mobile/src/model/user/user_repository.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/ui/user/perf_stats_screen.dart';
import 'package:lichess_mobile/src/utils/duration.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/player.dart';

final recentGamesProvider = FutureProvider.autoDispose
    .family<IList<ArchivedGameData>, UserId>((ref, userId) {
  final repo = ref.watch(gameRepositoryProvider);
  return Result.release(repo.getUserGames(userId));
});

final userProvider =
    FutureProvider.autoDispose.family<User, UserId>((ref, userId) {
  final repo = ref.watch(userRepositoryProvider);
  return Result.release(repo.getUser(userId));
});

class UserScreen extends ConsumerWidget {
  const UserScreen({required this.user, super.key});

  final LightUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConsumerPlatformWidget(
      ref: ref,
      androidBuilder: _buildAndroid,
      iosBuilder: _buildIos,
    );
  }

  Widget _buildAndroid(BuildContext context, WidgetRef ref) {
    final asyncUser = ref.watch(userProvider(user.id));
    return Scaffold(
      appBar: AppBar(
        title: PlayerTitle(userName: user.name, title: user.title),
      ),
      body: asyncUser.when(
        data: (user) {
          return UserScreenBody(user: user);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: _handleFetchUserError,
      ),
    );
  }

  Widget _buildIos(BuildContext context, WidgetRef ref) {
    final asyncUser = ref.watch(userProvider(user.id));
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: PlayerTitle(userName: user.name, title: user.title),
      ),
      child: asyncUser.when(
        data: (user) => SafeArea(child: UserScreenBody(user: user)),
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: _handleFetchUserError,
      ),
    );
  }

  Widget _handleFetchUserError(Object error, StackTrace stackTrace) {
    debugPrint(
      'SEVERE: [UserScreen] could not fetch user; $error\n$stackTrace',
    );
    return const Center(child: Text('Could not load user data.'));
  }
}

/// Common widget for [UserScreen] and [ProfileScreen].
///
/// The `showPlayerTitle` param is used by [ProfileScreen] because the username is
/// not present in the app bar.
///
/// Use `inCustomScrollView` parameter to return a [SliverPadding] widget needed
/// by [ProfileScreen].
class UserScreenBody extends StatelessWidget {
  const UserScreenBody({
    required this.user,
    this.inCustomScrollView = false,
    this.showPlayerTitle = false,
    super.key,
  });

  final User user;

  /// Should show the player title on top of the body.
  final bool showPlayerTitle;

  /// If set to `true` this widget will return a [SliverPadding] instead of a
  /// [ListView].
  final bool inCustomScrollView;

  @override
  Widget build(BuildContext context) {
    final playerTitle = PlayerTitle(
      userName: user.username,
      title: user.title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
    );
    final userFullName =
        user.profile?.fullName != null ? Text(user.profile!.fullName!) : null;
    final title = showPlayerTitle ? playerTitle : userFullName;
    final subTitle = showPlayerTitle ? userFullName : null;

    final list = [
      if (user.isPatron == true || title != null || subTitle != null)
        ListTile(
          leading: user.isPatron == true
              ? const Icon(LichessIcons.patron, size: 40)
              : null,
          title: title,
          subtitle: subTitle,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user.profile != null)
            Location(profile: user.profile!)
          else
            kEmptyWidget,
          const SizedBox(height: 5),
          Text(
            '${context.l10n.memberSince} ${DateFormat.yMMMMd().format(user.createdAt)}',
          ),
          const SizedBox(height: 5),
          Text(context.l10n.lastSeenActive(timeago.format(user.seenAt))),
          const SizedBox(height: 5),
          if (user.playTime != null)
            Text(
              context.l10n.tpTimeSpentPlaying(
                user.playTime!.total
                    .toDaysHoursMinutes(AppLocalizations.of(context)),
              ),
            )
          else
            kEmptyWidget,
        ],
      ),
      const SizedBox(height: 20),
      PerfCards(user: user),
      const SizedBox(height: 20),
      // TODO translate
      const Text('Recent games', style: Styles.sectionTitle),
      const SizedBox(height: 5),
      RecentGames(user: user),
    ];

    return inCustomScrollView
        ? SliverPadding(
            padding: Styles.bodyPadding,
            sliver: SliverList(
              delegate: SliverChildListDelegate(list),
            ),
          )
        : ListView(
            padding: Styles.bodyPadding,
            children: list,
          );
  }
}

class PerfCards extends StatelessWidget {
  const PerfCards({required this.user, super.key});

  final User user;

  @override
  Widget build(BuildContext context) {
    final List<Perf> userPerfs = Perf.values.where((element) {
      final p = user.perfs[element];
      return p != null &&
          p.numberOfGames > 0 &&
          p.ratingDeviation < kClueLessDeviation;
    }).toList(growable: false);

    return SizedBox(
      height: 106,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 3.0),
        scrollDirection: Axis.horizontal,
        itemCount: userPerfs.length,
        itemBuilder: (context, index) {
          final perf = userPerfs[index];
          final userPerf = user.perfs[perf]!;
          final bool isPerfWithoutStats =
              [Perf.puzzle, Perf.storm].contains(perf);
          return SizedBox(
            height: 100,
            width: 100,
            child: GestureDetector(
              onTap: isPerfWithoutStats
                  ? null
                  : () => _handlePerfCardTap(context, perf),
              child: PlatformCard(
                child: Padding(
                  padding: const EdgeInsets.all(6.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text(
                        perf.shortTitle,
                        style: TextStyle(color: textShade(context, 0.7)),
                      ),
                      Icon(perf.icon, color: textShade(context, 0.6)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          PlayerRating(
                            rating: userPerf.rating,
                            deviation: userPerf.ratingDeviation,
                            provisional: userPerf.provisional,
                            style: Styles.bold,
                          ),
                          const SizedBox(width: 3),
                          if (userPerf.progression != 0) ...[
                            Icon(
                              userPerf.progression > 0
                                  ? LichessIcons.arrow_full_upperright
                                  : LichessIcons.arrow_full_lowerright,
                              color: userPerf.progression > 0
                                  ? LichessColors.good
                                  : LichessColors.red,
                              size: 12,
                            ),
                            Text(
                              userPerf.progression.abs().toString(),
                              style: TextStyle(
                                color: userPerf.progression > 0
                                    ? LichessColors.good
                                    : LichessColors.red,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(width: 10),
      ),
    );
  }

  void _handlePerfCardTap(BuildContext context, Perf perf) {
    pushPlatformRoute(
      context: context,
      title: context.l10n.perfStats('${user.username} ${perf.title}'),
      builder: (context) => PerfStatsScreen(
        user: user,
        perf: perf,
        loggedInUser: user,
      ),
    );
  }
}

class RecentGames extends ConsumerWidget {
  const RecentGames({required this.user, super.key});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentGames = ref.watch(recentGamesProvider(user.id));

    return recentGames.when(
      data: (data) {
        return Column(
          children: ListTile.divideTiles(
            color: dividerColor(context),
            context: context,
            tiles: data.map((game) {
              final mySide = game.white.id == user.id ? Side.white : Side.black;
              final opponent =
                  game.white.id == user.id ? game.black : game.white;
              final opponentName = opponent.name == 'Stockfish'
                  ? context.l10n.aiNameLevelAiLevel(
                      opponent.name,
                      opponent.aiLevel.toString(),
                    )
                  : opponent.name;

              return PlatformListTile(
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push<void>(
                    MaterialPageRoute(
                      builder: (context) => ArchivedGameScreen(
                        gameData: game,
                        orientation:
                            user.id == game.white.id ? Side.white : Side.black,
                      ),
                    ),
                  );
                },
                leading: Icon(game.perf.icon),
                title: PlayerTitle(
                  userName: opponentName,
                  title: opponent.title,
                  rating: opponent.rating,
                ),
                subtitle: Text(
                  timeago.format(game.lastMoveAt),
                  style: TextStyle(
                    color: textShade(context, Styles.subtitleOpacity),
                  ),
                ),
                trailing: game.winner == mySide
                    ? const Icon(
                        CupertinoIcons.plus_square_fill,
                        color: LichessColors.good,
                      )
                    : const Icon(
                        CupertinoIcons.minus_square_fill,
                        color: LichessColors.red,
                      ),
              );
            }),
          ).toList(growable: false),
        );
      },
      error: (error, stackTrace) {
        debugPrint(
          'SEVERE: [UserScreen] could not load user games; $error\n$stackTrace',
        );
        return const Text('Could not load games.');
      },
      loading: () => const CenterLoadingIndicator(),
    );
  }
}

class Location extends StatelessWidget {
  const Location({required this.profile, super.key});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (profile.country != null)
          CachedNetworkImage(
            imageUrl: lichessFlagSrc(profile.country!),
            errorWidget: (_, __, ___) => kEmptyWidget,
          )
        else
          kEmptyWidget,
        const SizedBox(width: 10),
        Text(profile.location ?? ''),
      ],
    );
  }
}

String lichessFlagSrc(String country) {
  return '$kLichessHost/assets/images/flags/$country.png';
}
