# Windows Server 2022 Installation (Post-VM Provisioning)

This document explains how to install Windows Server 2022 inside a freshly provisioned VM created in Hyper-V.

---

## Step 2 – Begin Windows Setup Inside the VM

⚠️ **Important:** After powering on the VM, you must quickly press any key when you see the message:

Press any key to boot from CD or DVD...


- If you miss it, the VM will attempt to boot from the empty virtual hard disk and fail.  
- If that happens, simply restart the VM and watch carefully.

### Procedure
1. In **Hyper-V Manager**, right-click the VM (e.g., `DC01`) → **Connect**.  
2. In the VM console, when prompted, press any key to boot from the **Windows Server 2022 ISO**.  
3. On the Windows Setup screen:
   - Select **Language**, **Time**, and **Keyboard layout**.  
   - Click **Next → Install now**.  
   - If asked, enter a product key or select **I don’t have a product key** to install in evaluation mode.  
   - Choose the edition required for your lab (**Windows Server 2022 Datacenter (Desktop Experience)** is recommended).  
   - Accept the license terms → click **Next**.  
   - Select **Custom: Install Windows only (advanced)**.  
   - Highlight the virtual hard disk (leave unallocated unless you want custom partitions) → click **Next**.  

### The installer will:
- Copy files  
- Install features  
- Apply updates  
- Reboot several times  

⚠️ **Do not press any key after the first reboot**, or you will loop back into setup.

---

## Step 3 – Complete OOBE (Out-of-Box Experience)

1. When prompted, set a strong **Administrator password**.  
2. At the `Ctrl+Alt+Del` screen, log in as **Administrator**.  
3. Remove the ISO so future boots load directly from the installed system disk:

```powershell
Set-VMDvdDrive -VMName "DC01" -Path $null
```
## ✅ Result

At this point:

- Windows Server 2022 is fully installed on your VM.  
- You can now proceed to post-install configuration:
  - Rename the computer (e.g., `DC01`)  
  - Assign static IP addressing  
  - Install **Active Directory Domain Services (AD DS)**, **DNS**, and **DHCP** (next steps in the build guide)  
