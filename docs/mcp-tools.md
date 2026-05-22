# Surface MCP MVP

## Objectif

Garder très peu de tools pour préserver le contexte du LLM. Les workflows complexes doivent être décrits dans des skills qui utilisent principalement `execute_editor_script`.

## Tools MVP

### execute_editor_script

Exécute un script GDScript complet dans l'éditeur Godot.

Input:

```json
{
  "code": "extends RefCounted\n\nfunc run(api: GodotMcpApi, args: Dictionary) -> Dictionary:\n\treturn api.success({})",
  "args": {},
  "timeout_ms": 5000
}
```

Champs:

- `code`: script GDScript complet.
- `args`: dictionnaire transmis à `run`.
- `timeout_ms`: optionnel, limité par la configuration plugin.

Output:

```json
{
  "ok": true,
  "data": {},
  "warnings": [],
  "meta": {}
}
```

Ou:

```json
{
  "ok": false,
  "error": {
    "code": "SCRIPT_COMPILE_ERROR",
    "message": "...",
    "details": {}
  },
  "warnings": [],
  "meta": {}
}
```

Notes d'implémentation:

- Le script est exécuté sur le main thread.
- Le plugin injecte `GodotMcpApi`.
- Le retour est validé et normalisé.
- Les erreurs de compilation doivent inclure ligne/colonne si Godot les expose.

### get_editor_state

Retourne un snapshot compact de l'état de l'éditeur.

Input:

```json
{}
```

Output recommandé:

```json
{
  "ok": true,
  "data": {
    "godot_version": "4.4",
    "project_path": "/path/to/project",
    "current_scene_path": "res://Main.tscn",
    "current_scene_name": "Main",
    "selection": ["/root/Main/Player"],
    "is_playing": false
  }
}
```

Ce tool existe pour éviter d'utiliser `execute_editor_script` juste pour vérifier le contexte de base.

### get_scene_snapshot

Retourne la hiérarchie de la scène courante.

Input:

```json
{
  "include_properties": false,
  "max_depth": 32
}
```

Output recommandé:

```json
{
  "ok": true,
  "data": {
    "scene_path": "res://Main.tscn",
    "root": {
      "name": "Main",
      "type": "Node2D",
      "path": "/Main",
      "children": []
    }
  }
}
```

Pour le MVP, garder les propriétés désactivées par défaut. Les propriétés complètes peuvent être volumineuses.

### get_logs

Retourne les logs récents capturés par le plugin.

Input:

```json
{
  "source": "editor",
  "limit": 200
}
```

Sources MVP:

- `editor`: logs générés par le plugin MCP et erreurs du runner.

Source future:

- `game`: logs du jeu en cours via debugger/autoload.

Output recommandé:

```json
{
  "ok": true,
  "data": {
    "entries": [
      {
        "level": "info",
        "message": "MCP server started",
        "time": "2026-05-22T10:00:00Z"
      }
    ]
  }
}
```

### run_project

Lance le projet ou une scène spécifique.

Input:

```json
{
  "scene_path": ""
}
```

Comportement:

- si `scene_path` est vide, lancer le projet courant;
- sinon lancer la scène spécifiée;
- retourner l'état de lancement.

Output recommandé:

```json
{
  "ok": true,
  "data": {
    "is_playing": true,
    "scene_path": "res://Main.tscn"
  }
}
```

### stop_project

Arrête le projet en cours d'exécution.

Input:

```json
{}
```

Output recommandé:

```json
{
  "ok": true,
  "data": {
    "is_playing": false
  }
}
```

## Pourquoi Pas Plus De Tools

Ne pas ajouter de tools spécialisés pour:

- créer un node;
- modifier une propriété;
- créer une scène;
- connecter un signal;
- configurer l'input map;
- créer une ressource;
- générer du UI.

Ces opérations doivent être faites par `execute_editor_script` avec des skills qui fournissent des exemples fiables.

Exceptions futures possibles:

- une action est utilisée extrêmement souvent;
- une action a besoin d'une validation que le script runner ne peut pas fournir;
- un client MCP a des limites qui rendent le script runner insuffisant;
- une opération doit être streamée ou suivie comme job long.

## Schémas Et Descriptions

Les descriptions MCP doivent être courtes et orientées recherche.

Exemple pour `execute_editor_script`:

```text
Execute a complete GDScript editor script inside Godot. Use this for scene editing,
node creation, resource changes, project settings, input map, signals, UI layout,
and other editor automation. The script must extend RefCounted and define
run(api: GodotMcpApi, args: Dictionary) -> Dictionary.
```

## Mapping Vers Skills

Le tool `execute_editor_script` est généraliste. Le choix du workflow doit venir des skills.

Exemples:

- skill `godot-scene-editing`: créer/renommer/reparenter nodes avec UndoRedo;
- skill `godot-ui`: manipuler `Control`, anchors, containers, themes;
- skill `godot-debugging`: lire état, logs, run/stop, corriger erreurs;
- skill `godot-resources`: charger/sauver ressources, importer assets;
- skill `godot-input`: modifier `InputMap` et project settings.

## Resources Futures

Les MCP resources sont reportées après le MVP, mais les URIs cibles devraient être gardées en tête:

- `godot://editor/state`
- `godot://scene/current`
- `godot://scene/tree`
- `godot://selection/current`
- `godot://logs/recent`
- `godot://project/settings`

Quand ces resources seront ajoutées, elles devront éviter de dupliquer une grosse surface de tools.
