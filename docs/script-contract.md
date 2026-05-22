# Contrat D'Exécution Des Scripts

## Principe

Le LLM envoie toujours un script GDScript complet au tool MCP `execute_editor_script`.

Le plugin Godot compile ce script, l'instancie, puis appelle une fonction standard:

```gdscript
func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
```

Le retour est un `Dictionary` normalisé, idéalement créé avec `api.success(...)` ou `api.error(...)`.

## Format Obligatoire

Tout script envoyé par le LLM doit suivre ce format:

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	return api.success({
		"message": "ok"
	})
```

Règles:

- `extends RefCounted` est obligatoire.
- `run(api: GodotMcpApi, args: Dictionary) -> Dictionary` est obligatoire.
- `run` doit retourner un `Dictionary`.
- Les succès doivent utiliser `api.success(data)`.
- Les erreurs attendues doivent utiliser `api.error(code, message, details)`.
- Les mutations de scène doivent utiliser les helpers UndoRedo de `api`.

## Appel MCP

Exemple de payload conceptuel:

```json
{
  "code": "extends RefCounted\n\nfunc run(api: GodotMcpApi, args: Dictionary) -> Dictionary:\n\treturn api.success({\"name\": api.get_current_scene().name})",
  "args": {}
}
```

## Résultat Normalisé

Succès:

```gdscript
{
	"ok": true,
	"data": {},
	"warnings": [],
	"meta": {}
}
```

Erreur:

```gdscript
{
	"ok": false,
	"error": {
		"code": "ERROR_CODE",
		"message": "Human readable message",
		"details": {}
	},
	"warnings": [],
	"meta": {}
}
```

Le runner doit accepter seulement ces formes et convertir les erreurs internes en erreurs MCP structurées. Les warnings Godot émis pendant la compilation, l'instanciation ou l'exécution du script doivent être ajoutés au champ `warnings`, y compris quand le résultat est une erreur structurée.

## GodotMcpApi

`GodotMcpApi` est l'objet typé injecté dans les scripts. Il encapsule les accès utiles à l'éditeur et impose les conventions du MCP.

Responsabilités:

- fournir les helpers `success`, `error`, `warning`;
- exposer l'état de l'éditeur de manière stable;
- faciliter les mutations undoables;
- gérer les chemins `res://`;
- éviter que chaque script réimplémente les mêmes patterns Godot;
- rendre les skills plus courtes et plus fiables.

Interface MVP recommandée:

```gdscript
class_name GodotMcpApi
extends RefCounted

func success(data: Dictionary = {}, meta: Dictionary = {}) -> Dictionary
func error(code: String, message: String, details: Dictionary = {}) -> Dictionary
func warning(message: String, details: Dictionary = {}) -> void

func get_editor_interface() -> EditorInterface
func get_current_scene() -> Node
func get_selection() -> Array[Node]
func get_scene_tree_snapshot(root: Node = null, max_depth: int = 32, include_properties: bool = false, root_path: String = "", max_length: int = 0) -> Dictionary

func get_undo_redo() -> EditorUndoRedoManager
func create_undo_action(name: String) -> void
func add_do_method(object: Object, method: StringName, args: Array = []) -> void
func add_undo_method(object: Object, method: StringName, args: Array = []) -> void
func add_do_property(object: Object, property: StringName, value: Variant) -> void
func add_undo_property(object: Object, property: StringName, value: Variant) -> void
func commit_undo_action() -> void
func cancel_undo_action() -> void

func require_res_path(path: String) -> String
func load_resource(path: String) -> Resource
func save_resource(resource: Resource, path: String = "") -> Dictionary
func rescan_filesystem() -> void
```

L'API exacte peut évoluer, mais les noms MVP doivent rester stables une fois documentés dans les skills.

## Helpers De Résultat

Les scripts ne doivent pas construire le résultat à la main sauf cas exceptionnel.

Exemple:

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	return api.success({
		"scene_name": scene.name,
		"scene_path": scene.scene_file_path,
	})
```

## Mutations UndoRedo

Toute mutation de scène doit être undoable.

Exemple pour renommer un node:

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var selected := api.get_selection()
	if selected.is_empty():
		return api.error("NO_SELECTION", "Select a node before renaming")

	var node := selected[0]
	var old_name := node.name
	var new_name := String(args.get("name", "RenamedNode"))

	api.create_undo_action("Rename Node")
	api.add_do_property(node, &"name", new_name)
	api.add_undo_property(node, &"name", old_name)
	api.commit_undo_action()

	return api.success({
		"old_name": old_name,
		"new_name": new_name,
	})
```

Les skills doivent répéter cette règle: si le script modifie la scène, il doit utiliser UndoRedo.

## Création De Nodes

Exemple:

```gdscript
extends RefCounted

func run(api: GodotMcpApi, args: Dictionary) -> Dictionary:
	var scene := api.get_current_scene()
	if scene == null:
		return api.error("NO_SCENE", "No scene is currently open")

	var node := Node2D.new()
	node.name = String(args.get("name", "GeneratedNode"))

	api.create_undo_action("Create Node")
	api.add_do_method(scene, &"add_child", [node])
	api.add_do_method(node, &"set_owner", [scene])
	api.add_undo_method(scene, &"remove_child", [node])
	api.commit_undo_action()

	return api.success({
		"node_name": node.name,
		"parent": scene.name,
	})
```

Le plugin doit s'assurer que les objets créés restent valides après l'action UndoRedo. Si nécessaire, fournir un helper dédié `api.create_child_node(parent, node, action_name)` dans une version ultérieure.

## Validation Du Runner

Le runner doit valider:

- le script n'est pas vide;
- la taille est sous `max_script_chars`;
- le script compile avec `GDScript.reload()`;
- l'instance peut être créée;
- l'instance expose `run`;
- le retour de `run` est un `Dictionary`;
- le retour contient `ok`;
- si `ok == true`, `data` existe ou est ajouté;
- si `ok == false`, `error.code` et `error.message` existent;
- les exceptions ou erreurs Godot sont converties en `SCRIPT_RUNTIME_ERROR`.

## Erreurs Standard

Codes recommandés:

- `INVALID_SCRIPT`: script vide, trop grand ou forme interdite.
- `SCRIPT_COMPILE_ERROR`: erreur de compilation GDScript.
- `MISSING_RUN_METHOD`: le script ne définit pas `run`.
- `SCRIPT_RUNTIME_ERROR`: erreur pendant l'exécution.
- `INVALID_RESULT`: le script retourne une forme invalide.
- `NO_SCENE`: aucune scène active.
- `NO_SELECTION`: aucune sélection active.
- `INVALID_PATH`: chemin interdit ou invalide.
- `RESOURCE_ERROR`: chargement/sauvegarde de ressource échoué.
- `UNDO_REQUIRED`: mutation détectée ou demandée sans UndoRedo, si cette validation est possible.

## Limitations Connues

GDScript n'offre pas une sandbox fiable pour empêcher tout usage d'APIs dangereuses. Le contrat V1 est une convention forte pour un environnement local de confiance, pas une frontière de sécurité.
