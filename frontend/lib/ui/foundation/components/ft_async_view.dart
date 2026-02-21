import 'package:flutter/material.dart';

import '../../components/ft_components.dart';

class FTAsyncView extends StatelessWidget {
  const FTAsyncView({
    super.key,
    required this.loading,
    required this.error,
    required this.empty,
    required this.onRetry,
    required this.data,
    required this.loadingView,
    required this.emptyView,
  });

  final bool loading;
  final String? error;
  final bool empty;
  final VoidCallback onRetry;
  final Widget data;
  final Widget loadingView;
  final Widget emptyView;

  @override
  Widget build(BuildContext context) {
    return FTLoadStateLayout(
      loading: loading,
      error: error,
      onRetry: onRetry,
      empty: empty,
      emptyState: emptyView,
      loadingState: loadingView,
      child: data,
    );
  }
}

class FTInlineErrorState extends StatelessWidget {
  const FTInlineErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FTErrorState(
      message: message,
      onRetry: onRetry,
    );
  }
}
