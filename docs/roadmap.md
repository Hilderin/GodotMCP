# Roadmap D'Implémentation

## Phase 0: Squelette Projet

Objectif: créer une base de plugin Godot chargeable.

Livrables:

- `addons/godot_mcp/plugin.cfg`;
- `addons/godot_mcp/plugin.gd`;
- settings plugin pour host/port/enabled;
- log minimal dans la console Godot;
- documentation d'installation locale.

Critères d'acceptation:

- le plugin s'active dans Godot 4.4+;
- le plugin démarre et s'arrête sans erreur;
- les settings sont visibles ou au moins configurables.

## Phase 1: Serveur MCP HTTP Minimal

Objectif: permettre à un client MCP HTTP de découvrir les tools.

Livrables:

- serveur HTTP localhost;
- parsing JSON-RPC;
- handshake MCP minimal;
- `tools/list`;
- erreurs JSON-RPC propres;
- tool registry interne.

Critères d'acceptation:

- un client peut se connecter au plugin;
- `tools/list` retourne les tools MVP;
- une requête invalide retourne une erreur structurée.

## Phase 2: Script Runner

Objectif: exécuter un script complet envoyé via MCP.

Livrables:

- `ScriptRunner`;
- compilation avec `GDScript.new()` et `reload()`;
- validation `extends RefCounted` si détectable;
- validation méthode `run`;
- injection `GodotMcpApi`;
- normalisation result;
- erreurs `INVALID_SCRIPT`, `SCRIPT_COMPILE_ERROR`, `MISSING_RUN_METHOD`, `SCRIPT_RUNTIME_ERROR`, `INVALID_RESULT`.

Critères d'acceptation:

- un script trivial retourne `api.success`;
- une erreur de compilation retourne une erreur lisible;
- un script sans `run` est refusé;
- un retour invalide est refusé.

## Phase 3: GodotMcpApi MVP

Objectif: fournir une API stable pour les scripts générés.

Livrables:

- helpers `success`, `error`, `warning`;
- accès `EditorInterface`;
- accès scène courante;
- accès sélection;
- snapshot hiérarchie;
- helpers UndoRedo MVP;
- helpers chemin `res://`;
- log interne.

Critères d'acceptation:

- un script peut lire la scène courante;
- un script peut créer une action UndoRedo;
- un script peut retourner des warnings;
- les données retournées sont sérialisables JSON.

## Phase 4: Tools Core

Objectif: exposer les tools MVP autres que `execute_editor_script`.

Livrables:

- `execute_editor_script`;
- `get_editor_state`;
- `get_scene_snapshot`;
- `get_logs`;
- `run_project`;
- `stop_project`.

Critères d'acceptation:

- OpenCode peut inspecter l'état de l'éditeur sans script custom;
- OpenCode peut lancer/arrêter le projet;
- OpenCode peut récupérer les logs du plugin;
- la surface de tools reste courte.

## Phase 5: Skills MVP

Objectif: rendre le système utilisable par un LLM sans multiplier les tools.

Livrables:

- `godot-scene-editing`;
- `godot-debugging`;
- `godot-resources`;
- `godot-input-project-settings`;
- `godot-ui`;
- `godot-signals`.

Critères d'acceptation:

- chaque skill contient au moins un script complet valide;
- chaque skill rappelle la règle UndoRedo;
- les snippets retournent `api.success` ou `api.error`;
- les skills couvrent les workflows de base.

## Phase 6: Tests Et Validation

Objectif: éviter de casser le contrat script/MCP.

Tests recommandés:

- plugin load/unload;
- server start/stop;
- JSON-RPC invalid request;
- tools/list;
- `execute_editor_script` succès;
- erreur compilation;
- méthode `run` manquante;
- résultat invalide;
- `get_editor_state`;
- `get_scene_snapshot`;
- UndoRedo sur création de node;


Critères d'acceptation:

- les tests de contrat passent;
- les erreurs sont lisibles pour un LLM;
- aucun crash Godot sur script invalide courant.

## Backlog Après MVP

- Screenshots
- Obtention de la documentation à même un tool
- MCP resources `godot://...`.
- Capture des logs du jeu en cours.
- Sessions multi-éditeurs.
- UI dock plus complète.
- Helpers haut niveau dans `GodotMcpApi` pour création de nodes.
- Détection plus stricte des mutations sans UndoRedo.
- Packaging AssetLib.
- Auto-configuration OpenCode.
- Support de jobs longs et progress.
- Tests d'intégration avec un vrai client MCP.

## Ordre Recommandé Pour Un LLM Implémenteur

1. Créer le plugin minimal.
2. Ajouter le serveur HTTP et le registry MCP.
3. Ajouter `execute_editor_script` avec runner très strict.
4. Ajouter `GodotMcpApi.success/error`.
5. Ajouter les helpers lecture état/scène.
6. Ajouter UndoRedo helpers.
7. Ajouter les tools core.
8. Ajouter les skills MVP.
9. Ajouter les tests de contrat.

Ne pas commencer par les tools spécialisés. Le coeur du projet est le contrat scriptable.
