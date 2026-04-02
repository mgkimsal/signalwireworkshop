# Build Your First AI Phone Agent -- PHP Edition

> Duration: ~90 minutes | Level: Beginner
>
> Complete the [shared setup](../README.md) first (SignalWire account, API keys, ngrok).

---

## Section 3: Project Setup (5 min)

### Run the Setup Script

From the **workshop root** directory:

```bash
./setup.sh php
```

This clones the SignalWire PHP SDK and installs its dependencies via Composer.

### Verify Your Environment

```bash
php -v
composer --version
```

You need PHP 8.1 or higher and Composer installed.

### Project Structure

```
php/
├── README.md          # This file
└── steps/             # Checkpoint files for each section
```

---

## Quick Reference

| Concept | PHP Syntax |
|---------|-----------|
| Create agent | `new AgentBase(name: "...")` |
| Add prompt | `$agent->promptAddSection("Title", "body")` |
| Define tool | `$agent->defineTool(name, desc, params, handler)` |
| Add skill | `$agent->addSkill("datetime")` |
| Run agent | `$agent->run()` |

### Imports

```php
require 'vendor/autoload.php';

use SignalWire\Agent\AgentBase;
use SignalWire\SWAIG\FunctionResult;
use SignalWire\DataMap\DataMap;
```

---

## SDK Resources

- **SDK Repository:** [github.com/signalwire/signalwire-php](https://github.com/signalwire/signalwire-php)
- **Examples:** See the `examples/` folder in the SDK repository for complete agent examples
- **SignalWire Documentation:** [developer.signalwire.com](https://developer.signalwire.com)
