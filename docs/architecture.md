# Architecture Technique

## Objectif

Créer un MCP pour Godot qui permet à OpenCode ou tout autre client MCP de piloter l'éditeur Godot avec une surface de tools minimale.

Le projet privilégie un modèle scriptable: le LLM génère un script GDScript complet, l'envoie au plugin Godot via MCP, puis le plugin exécute une fonction `run(api, args)` dans l'éditeur.

## Décisions De Design

- Version cible: Godot 4.4+.
- Distribution principale: plugin Godot autonome.
- Transport principal: MCP Streamable HTTP exposé par le plugin sur `localhost`.
- Compatibilité clients: bridge stdio optionnel qui relaie les requêtes MCP stdio vers le plugin HTTP.
- Aucun serveur Node/Python obligatoire pour l'usage normal.
- Surface MCP minimale pour éviter de polluer le contexte du LLM.
- Les capabilities complexes vivent dans des skills par workflow, pas dans une longue liste de tools.
- Les MCP resources `godot://...` sont reportées après le MVP.
- Mode sécurité V1: local trust. Le plugin est un outil local de développement, pas une sandbox hostile.
- Toute mutation de scène doit passer par les helpers UndoRedo fournis par `GodotMcpApi`.

## Architecture Cible

```text
OpenCode / MCP client
        |
        | MCP Streamable HTTP
        v
Godot Editor Plugin
        |
        | request queue, main-thread execution
        v
Script Runner
        |
        | GodotMcpApi
        v
EditorInterface, EditorUndoRedoManager, EditorFileSystem, SceneTree
```

Bridge optionnel:

```text
MCP client without HTTP support
        |
        | MCP stdio
        v
godot-mcp-stdio-bridge
        |
        | HTTP localhost
        v
Godot Editor Plugin
```

## Plugin Godot

Le plugin est le coeur du système. Il doit:

- démarrer un serveur MCP HTTP local;
- exposer un petit ensemble de tools MCP;
- recevoir les appels `execute_editor_script`;
- compiler et instancier les scripts GDScript reçus;
- injecter un objet `GodotMcpApi` typé;
- exécuter le script sur le main thread de l'éditeur;
- normaliser les retours et les erreurs;
- préserver la réactivité de l'éditeur.

Structure recommandée:

```text
addons/godot_mcp/
├── plugin.cfg
├── plugin.gd
├── server/
│   ├── mcp_http_server.gd
│   ├── mcp_protocol.gd
│   └── mcp_tool_registry.gd
├── runner/
│   ├── script_runner.gd
│   ├── godot_mcp_api.gd
│   └── godot_mcp_result.gd
├── tools/
│   ├── execute_editor_script_tool.gd
│   ├── editor_state_tool.gd
│   ├── scene_snapshot_tool.gd
│   ├── logs_tool.gd
│   └── runtime_tools.gd
└── utils/
    ├── error_codes.gd
    ├── json_rpc.gd
    ├── log_buffer.gd
    └── path_utils.gd
```

## Exécution Main Thread

Les APIs d'éditeur Godot doivent être appelées depuis le thread principal.

Règles:

- Ne pas exécuter de mutation d'éditeur directement depuis un callback réseau.
- Enqueue les requêtes MCP entrantes.
- Drainer la queue dans `_process(delta)`.
- Limiter le nombre de commandes traitées par frame.
- Retourner une réponse asynchrone au client HTTP quand l'exécution est terminée.

Flux recommandé:

```text
HTTP request received
        |
        v
pending_requests.append(request)
        |
        v
plugin._process(delta)
        |
        v
script_runner.execute(request)
        |
        v
response sent
```

## Serveur MCP HTTP

Le serveur doit implémenter suffisamment du protocole MCP pour OpenCode et les clients modernes.

Pour le MVP, supporter:

- initialisation MCP;
- listing des tools;
- appel de tools;
- réponses JSON-RPC structurées;
- erreurs JSON-RPC propres.

Le plugin doit écouter uniquement sur `127.0.0.1` par défaut.

Paramètres plugin recommandés:

- `godot_mcp/http_host`: défaut `127.0.0.1`.
- `godot_mcp/http_port`: défaut `9700`.
- `godot_mcp/enabled`: défaut `true`.
- `godot_mcp/max_script_chars`: défaut `100000`.
- `godot_mcp/script_timeout_ms`: défaut `5000`.

## Bridge Stdio Optionnel

Le bridge stdio est une compatibilité, pas le coeur du projet.

Responsabilités:

- lire MCP JSON-RPC sur stdin;
- transférer les requêtes au plugin HTTP;
- retourner les réponses sur stdout;
- ne contenir aucune logique Godot;
- échouer clairement si le plugin n'est pas joignable.

Le bridge peut être écrit dans le runtime le plus simple à distribuer. Il ne doit pas devenir obligatoire pour les clients HTTP.

## Sécurité V1

Le MVP assume un usage local et de confiance.

Garde-fous requis quand même:

- écouter sur localhost seulement;
- limiter la taille du script;
- imposer un timeout ou un budget d'exécution raisonnable;
- refuser les scripts sans `extends RefCounted` et sans `run`;
- valider que le retour est un `Dictionary` normalisé;
- limiter les helpers filesystem à `res://` et `user://` sauf opt-in futur;
- retourner les erreurs de compilation/exécution sans crasher le plugin.

Non-objectifs V1:

- sandbox complète contre du code hostile;
- filtrage exhaustif des APIs Godot;
- exécution dans un processus isolé;
- permissions interactives par opération.

## Non-Objectifs V1

- Ne pas créer 50+ tools spécialisés.
- Ne pas reproduire toute l'API Godot sous forme de tools MCP.
- Ne pas supporter plusieurs sessions Godot simultanées.
- Ne pas implémenter les MCP resources dès le MVP.
- Ne pas créer une UI complexe de configuration.
- Ne pas garantir une sandbox de sécurité forte.
