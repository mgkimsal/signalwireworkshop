# Build Your First AI Phone Agent -- .NET (C#) Edition

> Duration: ~90 minutes | Level: Beginner
>
> Complete the [shared setup](../README.md) first (SignalWire account, API keys, ngrok).

---

## Section 3: Project Setup (5 min)

### Run the Setup Script

From the **workshop root** directory:

```bash
./setup.sh dotnet
```

This clones the SignalWire .NET SDK and builds it targeting .NET 8.0.

### Verify Your Environment

```bash
dotnet --version
```

You need .NET 8.0 or higher.

### Project Structure

```
dotnet/
├── README.md          # This file
└── steps/             # Checkpoint files for each section
```

---

## Quick Reference

| Concept | .NET Syntax |
|---------|-------------|
| Create agent | `new AgentBase(new AgentOptions { Name = "..." })` |
| Add prompt | `agent.PromptAddSection("Title", "body")` |
| Define tool | `agent.DefineTool(name, desc, params, handler)` |
| Add skill | `agent.AddSkill("datetime")` |
| Run agent | `agent.Run()` |

### Imports

```csharp
using SignalWire.Agent;
using SignalWire.SWAIG;
using SignalWire.DataMap;
```

---

## SDK Resources

- **SDK Repository:** [github.com/signalwire/signalwire-dotnet](https://github.com/signalwire/signalwire-dotnet)
- **Examples:** See the `examples/` folder in the SDK repository for complete agent examples
- **SignalWire Documentation:** [developer.signalwire.com](https://developer.signalwire.com)
