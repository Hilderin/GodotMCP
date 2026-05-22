# GodotMCP

Plugin Godot 4.4+ autonome destiné à exposer progressivement un serveur MCP HTTP local pour piloter l'éditeur.

## Installation Locale

1. Ouvrir ce dossier dans Godot 4.4+.
2. Aller dans `Project > Project Settings > Plugins`.
3. Activer le plugin `Godot MCP`.
4. Vérifier la console Godot: le plugin doit afficher un log `[GodotMCP] MCP HTTP server listening...`.

## Configuration

Les settings sont créés automatiquement à l'activation du plugin et sont configurables dans `Project Settings`:

- `godot_mcp/enabled`: active le plugin, défaut `true`.
- `godot_mcp/http_host`: host prévu pour le serveur MCP HTTP, défaut `127.0.0.1`.
- `godot_mcp/http_port`: port prévu pour le serveur MCP HTTP, défaut `9700`.

## MCP HTTP Minimal

Quand `godot_mcp/enabled` vaut `true`, le plugin démarre un serveur HTTP local sur `http://127.0.0.1:9700` par défaut.

Requête de découverte des tools:

```bash
curl -s http://127.0.0.1:9700 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

La phase 1 expose le handshake MCP minimal, `tools/list`, un registry interne des tools MVP et des erreurs JSON-RPC structurées. L'exécution effective des tools arrive dans les phases suivantes.
