function script:Initialize-YapLoqFilePickers {
    if(-not ('YapLoqFolderPicker' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class YapLoqFolderPicker {
 [ComImport,Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")] class Dialog {}
 [ComImport,Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface Item {
  void BindToHandler(IntPtr a,ref Guid b,ref Guid c,out IntPtr d);
  void GetParent(out Item p);
  void GetDisplayName(uint mode,out IntPtr name);
  void GetAttributes(uint mask,out uint attributes);
  void Compare(Item other,uint hint,out int order);
 }
 [ComImport,Guid("D57C7288-D4AD-4768-BE02-9D969532D960"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface OpenDialog {
  [PreserveSig] int Show(IntPtr owner);
  void SetFileTypes(uint n,IntPtr filters); void SetFileTypeIndex(uint i); void GetFileTypeIndex(out uint i);
  void Advise(IntPtr events,out uint cookie); void Unadvise(uint cookie);
  void SetOptions(uint options); void GetOptions(out uint options);
  void SetDefaultFolder(Item item); void SetFolder(Item item); void GetFolder(out Item item);
  void GetCurrentSelection(out Item item);
  void SetFileName([MarshalAs(UnmanagedType.LPWStr)]string name); void GetFileName(out IntPtr name);
  void SetTitle([MarshalAs(UnmanagedType.LPWStr)]string title);
  void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)]string text);
  void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)]string text);
  void GetResult(out Item item); void AddPlace(Item item,int place);
  void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)]string extension);
  void Close(int result); void SetClientGuid(ref Guid guid); void ClearClientData(); void SetFilter(IntPtr filter);
  void GetResults(out IntPtr items); void GetSelectedItems(out IntPtr items);
 }
 public static string Pick(IntPtr owner,string title){
  OpenDialog dialog=(OpenDialog)new Dialog(); Item item=null; IntPtr text=IntPtr.Zero;
  try {
   uint flags; dialog.GetOptions(out flags);
   dialog.SetOptions(flags|0x20u|0x40u|0x800u); // folders, filesystem, existing paths
   dialog.SetTitle(title); dialog.SetOkButtonLabel("Select folder");
   int hr=dialog.Show(owner); if(hr==unchecked((int)0x800704C7))return null;
   Marshal.ThrowExceptionForHR(hr); dialog.GetResult(out item);
   item.GetDisplayName(0x80058000u,out text); return Marshal.PtrToStringUni(text);
  } finally {
   if(text!=IntPtr.Zero)Marshal.FreeCoTaskMem(text);
   if(item!=null)Marshal.FinalReleaseComObject(item);
   Marshal.FinalReleaseComObject(dialog);
  }
 }
}
'@
    }
}
function script:Select-YapLoqFolder([string]$title='Choose a folder'){
    Initialize-YapLoqFilePickers
    return [YapLoqFolderPicker]::Pick(([Windows.Interop.WindowInteropHelper]::new($window)).Handle,$title)
}
