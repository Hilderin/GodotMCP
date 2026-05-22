# Stratégie De Skills

## Objectif

Les skills remplacent une grande surface de tools MCP. Elles donnent au LLM les recettes, contraintes et snippets nécessaires pour utiliser `execute_editor_script` correctement.

Les skills doivent être organisées par workflow, pas par liste exhaustive d'APIs Godot.

## Règles Communes À Toutes Les Skills

Chaque skill doit rappeler:

- utiliser `execute_editor_script` pour les changements d'éditeur;
- envoyer un script complet avec `extends RefCounted`;
- définir `func run(api: GodotMcpApi, args: Dictionary) -> Dictionary`;
- retourner `api.success(...)` ou `api.error(...)`;
- utiliser UndoRedo pour toute mutation de scène;
- utiliser les tools core pour inspecter l'état avant d'agir;
- garder les scripts courts et ciblés;
- retourner des données utiles au LLM pour continuer le travail.

Template de début recommandé pour toutes les skills:

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	return api.success({})
```

## Skills MVP

### godot-scene-editing

But:

- créer des nodes;
- supprimer des nodes;
- renommer des nodes;
- reparenter des nodes;
- modifier des propriétés;
- sauvegarder la scène.

Contenu attendu:

- comment obtenir la scène courante;
- comment résoudre un node par chemin;
- comment utiliser UndoRedo;
- exemples pour `Node2D`, `Control`, `Sprite2D`, `CollisionShape2D`, `Camera2D`;
- règles pour `owner` afin que les nodes soient sauvegardés dans la scène.

Exemple clé:

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var child := Node2D.new()
	child.name = String(args.get("name", "NewNode2D"))

	api.create_undo_action("Create Node2D")
	api.add_do_method(scene, &"add_child", [child])
	api.add_do_method(child, &"set_owner", [scene])
	api.add_undo_method(scene, &"remove_child", [child])
	api.commit_undo_action()

	return api.success({"created": child.name})
```

### godot-debugging

But:

- inspecter l'état de l'éditeur;
- lire les logs;
- lancer/arrêter le projet;
- reproduire une erreur;
- faire une petite modification et retester.

Contenu attendu:

- utiliser `get_editor_state` avant d'agir;
- utiliser `get_logs` après `run_project`;
- scripts pour inspecter scène courante et sélection;
- convention de réponse pour diagnostics.

### godot-resources

But:

- charger une ressource;
- créer une ressource;
- assigner une ressource à un node;
- sauvegarder une ressource;
- déclencher un rescan du filesystem.

Contenu attendu:

- utiliser `api.require_res_path`;
- utiliser `ResourceLoader` et `ResourceSaver` via helpers;
- vérifier les erreurs de chargement;
- éviter les chemins hors projet.

### godot-input-project-settings

But:

- lire/modifier `InputMap`;
- modifier `ProjectSettings`;
- créer des autoloads simples;
- sauvegarder les settings.

Contenu attendu:

- exemples `InputMap.add_action`;
- exemples `ProjectSettings.set_setting`;
- appeler `ProjectSettings.save()` si nécessaire;
- avertir que certaines modifications nécessitent un reload ou restart.

### godot-ui

But:

- créer des interfaces avec `Control`;
- utiliser containers;
- configurer anchors, offsets, size flags;
- créer des layouts propres.

Contenu attendu:

- préférer `VBoxContainer`, `HBoxContainer`, `MarginContainer`, `PanelContainer`;
- éviter de positionner manuellement tous les Controls sauf cas précis;
- exemples UndoRedo pour ajouter des Controls;
- conventions pour texte, thème et nommage.

### godot-signals

But:

- lister des signaux;
- connecter un signal à une méthode;
- déconnecter un signal;
- créer le squelette d'une méthode callback dans un script existant.

Contenu attendu:

- utiliser `Object.connect` avec `Callable`;
- vérifier les connexions existantes;
- éviter les doublons;
- retourner la liste des connexions créées.

## Format Des Fichiers De Skill

Si les skills sont stockées dans le repo, structure recommandée:

```text
skills/
├── godot-scene-editing.md
├── godot-debugging.md
├── godot-resources.md
├── godot-input-project-settings.md
├── godot-ui.md
└── godot-signals.md
```

Chaque skill devrait contenir:

- quand utiliser la skill;
- tools MCP à utiliser;
- règles critiques;
- snippets GDScript prêts à adapter;
- erreurs fréquentes;
- checklist de validation.

## Anti-Patterns À Documenter

Les skills doivent explicitement décourager:

- envoyer un snippet sans `extends RefCounted`;
- oublier `return api.success(...)`;
- modifier une scène sans UndoRedo;
- oublier `owner` sur un node ajouté à une scène sauvegardée;
- retourner des objets Godot bruts non sérialisables;
- écrire hors `res://` ou `user://`;
- supposer qu'une scène est ouverte sans vérifier;
- charger toutes les propriétés d'un gros arbre de scène sans limite.

## Relation Avec Les Tools MCP

Les tools restent stables et peu nombreux. Les skills peuvent évoluer rapidement avec de meilleurs snippets sans casser le protocole MCP.

Cette séparation est intentionnelle:

- tools: contrat stable entre client MCP et plugin;
- skills: connaissance évolutive pour guider le LLM;
- scripts générés: action ponctuelle adaptée au projet courant.
