# Documentation Technique GodotMCP

Cette documentation fixe les décisions de design du MVP et sert de base pour qu'un LLM puisse implémenter le projet.

## Ordre De Lecture

1. Lire `architecture.md` pour comprendre le modèle plugin Godot autonome, MCP HTTP et bridge stdio optionnel.
2. Lire `script-contract.md` pour implémenter le runner et `GodotMcpApi`.
3. Lire `mcp-tools.md` pour exposer seulement la surface MCP MVP.
4. Lire `skills.md` pour comprendre comment remplacer une grande liste de tools par des workflows documentés.
5. Lire `roadmap.md` pour suivre l'ordre d'implémentation.
6. Lire `implementation-guide.md` avant de commencer à coder.
7. Lire `../README.md` pour l'installation locale du plugin.

## Décisions Résumées

- Godot cible: 4.4+.
- Produit principal: plugin Godot autonome.
- Transport principal: MCP Streamable HTTP sur `127.0.0.1`.
- Compatibilité: bridge stdio optionnel.
- Tool principal: `execute_editor_script`.
- Contrat script: `extends RefCounted` + `func run(api: GodotMcpApi, args: Dictionary) -> Dictionary`.
- Résultat: `api.success(...)` ou `api.error(...)`.
- Mutations scène: UndoRedo obligatoire.
- Skills: organisées par workflow.
- MCP resources: après MVP.
