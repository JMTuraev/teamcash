import 'package:flutter/material.dart';

import 'package:teamcash/core/models/app_role.dart';

abstract final class TeamCashIcons {
  static const back = Icons.arrow_back_rounded;
  static const hub = Icons.hub_outlined;
  static const brand = Icons.link_rounded;
  static const wallet = Icons.wallet_outlined;
  static const walletLinked = Icons.account_balance_wallet_outlined;
  static const bolt = Icons.bolt_rounded;
  static const badge = Icons.badge_outlined;
  static const storefront = Icons.storefront_outlined;
  static const dashboard = Icons.insights_outlined;
  static const scan = Icons.qr_code_scanner_outlined;
  static const stores = Icons.home_outlined;
  static const activity = Icons.receipt_long_outlined;
  static const profile = Icons.person_rounded;
  static const login = Icons.login_rounded;
  static const chevronRight = Icons.chevron_right_rounded;
  static const chevronDown = Icons.keyboard_arrow_down_rounded;
  static const spark = Icons.auto_awesome_rounded;
  static const backspace = Icons.backspace_outlined;
  static const discover = Icons.explore_outlined;
  static const qrCode = Icons.qr_code_2_rounded;
  static const chat = Icons.chat_bubble_outline_rounded;
  static const person = Icons.person_outline_rounded;
  static const verify = Icons.verified_user_outlined;
  static const preview = Icons.visibility_outlined;
  static const cloudDone = Icons.cloud_done_outlined;
  static const phone = Icons.phone_android_rounded;
  static const sms = Icons.sms_outlined;
  static const warning = Icons.warning_amber_rounded;
  static const unlock = Icons.lock_open_outlined;
  static const show = Icons.visibility_outlined;
  static const hide = Icons.visibility_off_outlined;
  static const refresh = Icons.refresh_outlined;
  static const battery = Icons.battery_full_rounded;
  static const wifi = Icons.wifi_rounded;
  static const signal = Icons.signal_cellular_alt_rounded;
  static const premium = Icons.workspace_premium_outlined;
  static const info = Icons.info_outline;
  static const trendUp = Icons.trending_up_rounded;
  static const trendDown = Icons.trending_down_rounded;
  static const trendFlat = Icons.trending_flat_rounded;
  static const heart = Icons.favorite_rounded;
  static const heartOutline = Icons.favorite_border_rounded;
  static const location = Icons.location_on_outlined;
  static const locate = Icons.my_location_rounded;

  static IconData role(AppRole role) {
    return switch (role) {
      AppRole.owner => storefront,
      AppRole.staff => badge,
      AppRole.client => person,
    };
  }
}
