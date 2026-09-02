# Appx-Backup

A PowerShell script to create a signed offline backup (`.appx` package) of any Windows Store (UWP/AppX) application.  
It packs the app folder, generates a self‑signed certificate (using pure .NET – no dependency on the `Cert:` drive), signs the package, and saves both the `.appx` and the `.cer` file.

---

### Features
- **Console & GUI modes** – run with parameters for automation or launch the graphical interface (`-GUI`) for interactive use.
- **Automatic SDK detection** – finds the newest installed Windows SDK version.
- **Settings persistence** – remembers the last used paths in `%APPDATA%\AppxBackup\settings.xml`.
- **Real‑time logging** – shows the full output of `MakeAppx.exe` and `SignTool.exe` in the GUI log panel.
- **Progress indicator** – a marquee progress bar runs while the backup is being created.
- **Pure .NET certificate generation** – works even if the `Cert:` PowerShell drive is unavailable.

### Requirements
- **Windows 10/11** (x64)
- **PowerShell 5.1 or later** (run **as Administrator** for both backup creation and certificate installation)
- **Windows SDK** (10.0.18362.0 or newer) with `MakeAppx.exe` and `SignTool.exe` in the `x64` folder.  
  If the SDK is not installed, you can download it from the [official site](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/).

### Installation
1. Place the script `Appx-Backup.ps1` in any folder.
2. (Optional) Create a shortcut or alias for quick access.

### Usage

#### Console mode (default)
```powershell
.\Appx-Backup.ps1 -WSAppPath "<path_to_app_folder>" -WSAppOutputPath "<output_folder>" -WSTools "<path_to_SDK_tools_x64>"
```

If you omit any parameter, the script will prompt you interactively.

#### GUI mode
```powershell
.\Appx-Backup.ps1 -GUI
```
The GUI window lets you browse for the required folders and start the backup with a single click.  
All settings are automatically saved and restored on next launch.

### Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-WSAppPath` | Full path to the application folder inside `C:\Program Files\WindowsApps` | `"C:\Program Files\WindowsApps\Microsoft.RemoteDesktop_10.2.4012.0_x64__8wekyb3d8bbwe"` |
| `-WSAppOutputPath` | Destination folder for `.appx` and `.cer` files | `"C:\Backup"` |
| `-WSTools` | Path to the x64 tools folder of the Windows SDK (contains `MakeAppx.exe`, `SignTool.exe`) | `"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64"` |
| `-GUI` | (Switch) Launches the graphical interface instead of console mode | `-GUI` |

### Examples
- **Console**  
  ```powershell
  .\Appx-Backup.ps1 -WSAppPath "C:\Program Files\WindowsApps\Microsoft.RemoteDesktop_10.2.4012.0_x64__8wekyb3d8bbwe" -WSAppOutputPath "D:\AppBackups" -WSTools "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64"
  ```
- **GUI**  
  ```powershell
  .\Appx-Backup.ps1 -GUI
  ```

### What happens behind the scenes
1. Reads `AppxManifest.xml` to get the app name and publisher.
2. Packs the app folder into a compressed `.appx` using `MakeAppx.exe`.
3. Generates a self‑signed certificate using **.NET** classes (no dependency on the `Cert:` drive).
4. Exports the certificate to `.cer` (public) and `.pfx` (private key + password `password`).
5. Signs the `.appx` package using `SignTool.exe`.
6. Cleans up temporary files and leaves only the `.appx` and `.cer`.

### Installing the backup on another computer
1. **Install the certificate into the Local Machine → Trusted Root Certification Authorities store** – this is mandatory.  
   - Double‑click the `.cer` file → **Install Certificate** → select **Local Machine** → **Place all certificates in the following store** → **Trusted Root Certification Authorities** → Finish.  
   - Or use PowerShell (Admin):  
     ```powershell
     Import-Certificate -FilePath "path\to\file.cer" -CertStoreLocation "Cert:\LocalMachine\Root"
     ```
   > **Important**: installing the certificate into the current user's store (`CurrentUser\Root`) will **not** work for package installation – you must use `LocalMachine\Root`.

2. Install the `.appx` package by double‑clicking it or with:  
   ```powershell
   Add-AppxPackage -Path "path\to\file.appx"
   ```

### Troubleshooting
- **`MakeAppx.exe` not found** – verify that `-WSTools` points to the correct SDK `x64` folder.
- **Certificate creation fails** – ensure you run PowerShell as Administrator. The script now uses pure .NET, so the `Cert:` drive is not required.
- **SignTool error** – check that the `.pfx` file was created (temporary) and that the password `password` is used.
- **Installation error 0x800B0109** – this means the certificate was not installed into the **Local Machine\Trusted Root Certification Authorities** store. Re‑install the certificate as described above.

---

### Возможности
- **Консольный и графический режимы** – запускайте с параметрами для автоматизации или используйте `-GUI` для интерактивной работы.
- **Автоматическое определение SDK** – находится последняя установленная версия Windows SDK.
- **Сохранение настроек** – последние пути запоминаются в `%APPDATA%\AppxBackup\settings.xml`.
- **Логирование в реальном времени** – в GUI все выводы `MakeAppx.exe` и `SignTool.exe` отображаются в окне лога.
- **Индикатор прогресса** – во время создания бэкапа отображается бегущая полоса.
- **Генерация сертификата через .NET** – работает даже если диск `Cert:` недоступен в PowerShell.

### Требования
- **Windows 10/11** (x64)
- **PowerShell 5.1 или новее** (запускать **от имени администратора** для создания бэкапа и установки сертификата)
- **Windows SDK** (версия 10.0.18362.0 или выше) с `MakeAppx.exe` и `SignTool.exe` в папке `x64`.  
  Если SDK не установлен, скачайте его с [официального сайта](https://developer.microsoft.com/ru-ru/windows/downloads/windows-sdk/).

### Установка
1. Поместите скрипт `Appx-Backup.ps1` в любую папку.
2. (Опционально) создайте ярлык или псевдоним для быстрого запуска.

### Использование

#### Консольный режим (по умолчанию)
```powershell
.\Appx-Backup.ps1 -WSAppPath "<путь_к_папке_приложения>" -WSAppOutputPath "<папка_для_сохранения>" -WSTools "<путь_к_SDK_tools_x64>"
```

Если не указать какой‑либо параметр, скрипт запросит его в интерактивном режиме.

#### Режим GUI
```powershell
.\Appx-Backup.ps1 -GUI
```
В графическом окне можно выбрать папки через проводник и запустить создание бэкапа одной кнопкой.  
Все настройки автоматически сохраняются и восстанавливаются при следующем запуске.

### Параметры

| Параметр | Описание | Пример |
|----------|----------|--------|
| `-WSAppPath` | Полный путь к папке приложения в `C:\Program Files\WindowsApps` | `"C:\Program Files\WindowsApps\Microsoft.RemoteDesktop_10.2.4012.0_x64__8wekyb3d8bbwe"` |
| `-WSAppOutputPath` | Папка для сохранения файлов `.appx` и `.cer` | `"C:\Backup"` |
| `-WSTools` | Путь к папке x64 утилит Windows SDK (содержит `MakeAppx.exe`, `SignTool.exe`) | `"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64"` |
| `-GUI` | (Ключ) Запускает графический интерфейс вместо консольного режима | `-GUI` |

### Примеры
- **Консоль**  
  ```powershell
  .\Appx-Backup.ps1 -WSAppPath "C:\Program Files\WindowsApps\Microsoft.RemoteDesktop_10.2.4012.0_x64__8wekyb3d8bbwe" -WSAppOutputPath "D:\AppBackups" -WSTools "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64"
  ```
- **GUI**  
  ```powershell
  .\Appx-Backup.ps1 -GUI
  ```

### Что происходит внутри
1. Чтение `AppxManifest.xml` для получения имени приложения и издателя.
2. Упаковка папки приложения в сжатый `.appx` с помощью `MakeAppx.exe`.
3. Создание самоподписанного сертификата через **.NET** (без использования диска `Cert:`).
4. Экспорт сертификата в `.cer` (открытый ключ) и `.pfx` (закрытый ключ + пароль `password`).
5. Подпись `.appx`‑пакета с помощью `SignTool.exe`.
6. Удаление временных файлов, остаются только `.appx` и `.cer`.

### Установка бэкапа на другом компьютере
1. **Установите сертификат в хранилище Локальный компьютер → Доверенные корневые центры сертификации** – это обязательно.  
   - Дважды щёлкните по `.cer` → **Установить сертификат** → выберите **Локальный компьютер** → **Поместить все сертификаты в следующее хранилище** → **Доверенные корневые центры сертификации** → Далее → Готово.  
   - Или через PowerShell (администратор):  
     ```powershell
     Import-Certificate -FilePath "путь\файл.cer" -CertStoreLocation "Cert:\LocalMachine\Root"
     ```
   > **Важно**: установка сертификата в хранилище текущего пользователя (`CurrentUser\Root`) **не подойдёт** для установки пакета – используйте только `LocalMachine\Root`.

2. Установите `.appx` двойным щелчком или командой:  
   ```powershell
   Add-AppxPackage -Path "путь\файл.appx"
   ```

### Устранение неполадок
- **`MakeAppx.exe` не найден** – проверьте, что `-WSTools` указывает на правильную папку SDK `x64`.
- **Ошибка создания сертификата** – убедитесь, что PowerShell запущен от имени администратора. Скрипт теперь использует .NET, поэтому диск `Cert:` не требуется.
- **Ошибка подписи** – проверьте, что временный `.pfx` создан и используется пароль `password`.
- **Ошибка установки 0x800B0109** – означает, что сертификат не был установлен в хранилище **Local Machine\Trusted Root Certification Authorities**. Переустановите сертификат, как описано выше.
