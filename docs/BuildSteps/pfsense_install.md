# pfSense VM Installation Guide 🖥️

After running the `Deploy-PfSense.ps1` script, the pfSense virtual machines (pfSense-A, pfSense-B, pfSense-C) are created, ISO-mounted, and ready for installation.  
This guide explains how to use **Hyper-V Manager** to complete the pfSense installation.

---

## 1. Open Hyper-V Manager
1. On your Hyper-V host, press `Win + R`, type `virtmgmt.msc`, and press Enter.
2. You should see the three VMs: **pfSense-A**, **pfSense-B**, and **pfSense-C**.

---

## 2. Boot from the pfSense ISO
By default, the script sets the DVD drive (pfSense ISO) as the **first boot device**.  
If the VM doesn’t boot to the ISO:
1. Right-click the VM (e.g., `pfSense-A`) → **Settings**.
2. In the left pane, expand **Firmware**.
3. Move the **DVD Drive** above the **Hard Drive** in the **Boot Order**.
4. Click **Apply** → **OK**.

---

## 3. Install pfSense
1. Right-click the VM → **Connect…**.
2. Start the VM (click the green power button).
3. Follow the pfSense installer prompts:
   - Accept defaults unless you need custom disk layout.
   - Install to the virtual hard disk (20 GB+ created by the script).
   - When prompted, reboot.

---

## 4. Switch Boot Order Back to Hard Disk
After installation:
1. Shut down the VM if it’s still running from the ISO.
2. In Hyper-V Manager, right-click the VM → **Settings**.
3. Go to **Firmware** again.
4. Move the **Hard Drive** above the **DVD Drive** in the **Boot Order**.
5. Click **Apply** → **OK**.

---

## 5. First Boot from Disk
1. Start the VM again.
2. pfSense will now boot directly from its installed disk.
3. Proceed with initial configuration:
   - Assign WAN/LAN interfaces.
   - Set IP addresses and gateways.
   - Access the pfSense WebGUI from a LAN host.

---

✅ Repeat this process for **pfSense-A**, **pfSense-B**, and **pfSense-C**.  
Once complete, follow the network addressing & static route steps in the main lab guide.

---
