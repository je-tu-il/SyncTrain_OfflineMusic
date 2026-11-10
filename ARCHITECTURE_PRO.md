# Architecture Technique — SyncTrain OfflineMusic

## 1. Description
Fork de Syncthing/SyncTrain avec découverte hors-ligne de proximité et lecteur audio intégré pour dossiers synchronisés.

## 2. Spécifications
- **Pôle** : `01_APPLICATIONS_DESKTOP`
- **Port d'écoute** : `8094`
- **Architecture** : Serveur REST léger, interface web responsive, mode offline résilient.

## 3. Lancement Rapide
Double-cliquer sur `Lancer_Projet.bat` pour démarrer le serveur et ouvrir `http://localhost:8094`.
Pour exécuter la suite de tests unitaires, lancer `run_tests.bat`.
