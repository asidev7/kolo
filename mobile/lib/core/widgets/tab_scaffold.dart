import 'package:flutter/material.dart';

/// `Scaffold` d'un écran affiché sous la barre d'onglets de `HomeShell`.
///
/// La coquille dessine cette barre par-dessus le contenu (`extendBody`) : les
/// écrans ne peuvent donc pas la voir, et un `Scaffold` ordinaire poserait
/// leur bouton flottant et leurs snackbars *sous* la barre floutée.
///
/// Ce `Scaffold` en réserve la hauteur dans un `bottomNavigationBar` invisible.
/// Le bouton flottant et les snackbars se placent alors correctement au-dessus,
/// tandis que le corps continue de défiler dessous : avec `extendBody`, la
/// hauteur réservée est rendue au corps.
class KoloTabScaffold extends StatelessWidget {
  const KoloTabScaffold({
    required this.body,
    super.key,
    this.appBar,
    this.floatingActionButton,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      // `extendBody` de la coquille transmet la hauteur de la barre d'onglets
      // dans `MediaQuery.padding.bottom`.
      bottomNavigationBar: SizedBox(
        height: MediaQuery.paddingOf(context).bottom,
      ),
      body: body,
    );
  }
}
