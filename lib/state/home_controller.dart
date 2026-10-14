import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/recent_list.dart';
import 'providers.dart';

class HomeController extends Notifier<List<RecentList>> {
  @override
  List<RecentList> build() => ref.watch(recentsStoreProvider).all();

  void refresh() {
    state = ref.read(recentsStoreProvider).all();
  }

  Future<void> remove(String uri) async {
    await ref.read(recentsStoreProvider).remove(uri);
    try {
      await ref.read(safGatewayProvider).releasePermission(uri);
    } catch (_) {
      // The permission may already be gone.
    }
    refresh();
  }
}

final NotifierProvider<HomeController, List<RecentList>> homeControllerProvider =
    NotifierProvider<HomeController, List<RecentList>>(HomeController.new);
