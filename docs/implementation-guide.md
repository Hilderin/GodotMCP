# Guide Pour LLM Implémenteur

## Mission

Implémenter un plugin Godot 4.4+ qui expose un serveur MCP HTTP local et permet à un client comme OpenCode d'exécuter des scripts GDScript complets dans l'éditeur via `execute_editor_script`.

Le projet ne doit pas commencer par une grande liste de tools. La priorité est un runtime scriptable fiable, typé et bien documenté.

## Contraintes Non Négociables

- Le plugin doit être autonome pour l'usage normal.
- Aucun serveur Node/Python ne doit être requis pour parler à Godot si le client supporte MCP HTTP.
- Le bridge stdio est optionnel et ne doit contenir aucune logique Godot.
- La surface MCP MVP contient seulement `execute_editor_script`, `get_editor_state`, `get_scene_snapshot`, `get_logs`, `run_project`, `stop_project`.
- Le script envoyé par le LLM doit toujours être complet.
- Le script doit définir `func run(api: GodotMcpApi, args: Dictionary) -> Dictionary`.
- Le runner doit valider et normaliser tous les retours.
- Les mutations de scène doivent utiliser UndoRedo via `GodotMcpApi`.
- Les erreurs doivent être lisibles par un LLM et contenir un code stable.

## Première Implémentation Recommandée

Créer d'abord le plugin minimal:

```text
addons/godot_mcp/plugin.cfg
addons/godot_mcp/plugin.gd
```

Puis ajouter les modules dans cet ordre:

```text
addons/godot_mcp/server/mcp_http_server.gd
addons/godot_mcp/server/mcp_protocol.gd
addons/godot_mcp/server/mcp_tool_registry.gd
addons/godot_mcp/runner/godot_mcp_api.gd
addons/godot_mcp/runner/script_runner.gd
addons/godot_mcp/utils/error_codes.gd
addons/godot_mcp/utils/log_buffer.gd
```

Ne pas ajouter les skills avant que `execute_editor_script` fonctionne.

## Boucle D'Exécution

Le serveur HTTP ne doit pas muter l'éditeur directement.

Implémenter une queue:

```text
HTTP handler -> enqueue request -> plugin._process -> dispatch tool -> send response
```

Cette structure évite les appels éditeur hors main thread et garde le plugin extensible.

## Runner Minimal

Le runner doit faire exactement ceci:

1. Vérifier que `code` est une string non vide.
2. Vérifier la taille maximale.
3. Vérifier la présence textuelle de `extends RefCounted`.
4. Compiler avec `GDScript.new()` et `reload()`.
5. Instancier le script.
6. Vérifier `has_method("run")`.
7. Créer `GodotMcpApi`.
8. Appeler `run(api, args)`.
9. Valider que le retour est un `Dictionary`.
10. Normaliser `warnings` et `meta`.
11. Retourner une réponse MCP.

## GodotMcpApi Minimal

Implémenter d'abord seulement:

```gdscript
class_name GodotMcpApi
extends RefCounted

func success(data: Dictionary = {}, meta: Dictionary = {}) -> Dictionary:
	return {
		"ok": true,
		"data": data,
		"warnings": [],
		"meta": meta,
	}

func error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
			"details": details,
		},
		"warnings": [],
		"meta": {},
	}
```

Ajouter ensuite les accès éditeur et UndoRedo.

## Définition De Done MVP

Le MVP est terminé quand:

- le plugin démarre dans Godot 4.4+;
- un client MCP peut lister les tools;
- `execute_editor_script` peut exécuter un script trivial;
- les erreurs de compilation sont retournées proprement;
- `get_editor_state` retourne scène courante, sélection et état play;
- `get_scene_snapshot` retourne la hiérarchie courante;
- `get_logs` retourne les logs du plugin;
- `run_project` et `stop_project` fonctionnent;
- un script peut créer un node via UndoRedo;
- la documentation des skills existe au moins sous forme de fichiers markdown.

## Pièges À Éviter

- Ne pas transformer `execute_editor_script` en mini-langage maison.
- Ne pas ajouter un tool MCP par action Godot.
- Ne pas exécuter le code directement depuis le callback HTTP.
- Ne pas retourner des objets Godot bruts dans le JSON.
- Ne pas ignorer les erreurs de compilation GDScript.
- Ne pas oublier `owner` quand un node doit être sauvegardé dans une scène.
- Ne pas écrire un bridge stdio avant que le plugin HTTP fonctionne.
- Ne pas viser une sandbox forte dans le MVP.
