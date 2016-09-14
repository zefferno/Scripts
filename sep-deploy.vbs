' //***************************************************************************
' // ***** Script Header *****
' //
' // Solution:  Symantec Endpoint Protection Deployment
' // File:      SEP.vbs
' // Author: 	Zefferno
' //
' // Version History:
' // 1.0.0   22/07/2009	First Version
' // 1.0.1	 25/09/2009 Changed registry check before log initilization, for faster execution
' // 1.0.2   06/03/2011 Added 64bit setup client support
' // 1.0.3   14/07/2011 Added support in Sub Main for 12.1 version
' //
' // ***** End Header *****
' //***************************************************************************

' Global Registry keys paths and values
Const regSEPVersionPath = "HKLM\Software\Symantec\Symantec Endpoint Protection\SMC\Version"
' New Server IP
Const regSEPIpPath = "HKLM\Software\Symantec\Symantec Endpoint Protection\SMC\SYLINK\SyLink\LastServerIP"
' Current Server IP
' * Fill in your SEP server IP address here
Const regCurrentServerIP = "172.30.1.1"

' Global Constants
Const strSEPVersion = "11.0"
Const strSEPNewVersion = "12.1"
Const strLogFile = "sep_deployment_script.log"
Const strMSIInstallLog = "sep_msi_install.log"

Const intMaxLogSize = 5000

' * Fill in your UNC path hosting the setup for Windows x32 and x64 here
Const strSEP_W32_UNCPath = "\\SEP-SERVER\Deploy\x32"
Const strSEP_W64_UNCPath = "\\SEP-SERVER\Deploy\x64"

' * This will contain the dropper (sylinker used to link the client to the management server)
Const strSEPRelinkFiles = "\\mydomain.local\NETLOGON\SEP\drop\*.*"

' This overrides the registry key setting
Const bolLogging = True

' Global variables
Dim strLogFullPath
Dim bolLoggingEnabled : bolLoggingEnabled = False
Dim objScriptingFramework
Dim objLogging
Dim objRegistry

' Call main
Main()

' Cleanup
Set objLogging = Nothing
Set objScriptingFramework = Nothing
Set objRegistry = Nothing

Sub Main
	Dim bolMoveClient : bolMoveClient = False
	Dim strVersion
	Dim intRet
	
	On Error Resume Next
	
	Set objRegistry = New WindowsRegistry
	
	' Check installation
	If objRegistry.ReadKey(regSEPVersionPath) = strSEPVersion Or objRegistry.ReadKey(regSEPVersionPath) = strSEPNewVersion Then			
		' Check if we need to relink to new server
		If objRegistry.ReadKey(regSEPIpPath) <> regCurrentServerIP Then
			bolMoveClient = True		
		Else
			Exit Sub
		End If
	End If
		
	' Create global class instances
	Set objLogging = New Logging
	Set objScriptingFramework = New ScriptingFramework
	
	' Build the temporary path to the log file  
	If Not CheckIfDirExists(GetEnvironmentVariable("TEMP")) Then
		strLogFullPath = "C:\"
	Else
		strLogFullPath = GetEnvironmentVariable("TEMP")
	End If

	' Check if script debugging is disabled or enabled
	If objScriptingFramework.DebugLevel > "0" Or bolLogging Then 
		objLogging.LoggingEnabled = True
	Else
		objLogging.LoggingEnabled = False
	End If

	' Initilzing the log class
	objLogging.InitilizeFile strLogFullPath & "\" & strLogFile, intMaxLogSize
	
	' Start the main logic
	objLogging.WriteToFile Logging_Information, "*******************************************************************"
	objLogging.WriteToFile Logging_Information, " Starting main logic..."
	objLogging.WriteToFile Logging_Information, "*******************************************************************"
	objLogging.WriteToFile Logging_Information, ""
	
	If bolMoveClient Then	
		objLogging.WriteToFile Logging_Information, "Relinking SEP..."	
		' Relink client to new server
		RelinkServer		
		Exit Sub
	End If
	
	objLogging.WriteToFile Logging_Error, "SEP is not installed, installing SEP..."	
	
	ShowDeleyedPopup "You don't have Endpoint Protection Installed!" & vbNewLine & _
					 "SEP will be installed now." & vbNewLine & _
					 "Process may take from 5-15 mintues, depanding on your computer and network speed." & vbNewLine & _
					 "Please be patient and do not restart your computer." & vbNewLine & _
					 "For more information please contact your local IT department.", "Information", 30, 1
	
	objLogging.WriteToFile Logging_Information, "Checking for incompatible services..."		
	
	'Disable and stop incompatible services
	StopAndDisableService "IPS Core Service (IPSSVC)"
	
	'Install		
	InstallProcedure	
End Sub

Sub InstallProcedure
	Dim strCommand, objWSHShell, intRet
	
	On Error Resume Next
	
	Set objWSHShell = WScript.CreateObject("WScript.Shell") 
	
	If WScript.Arguments.Count = 0 Then
		' Check for 64Bit OS to fit proper installation
		If Check64Bit Then
			objLogging.WriteToFile Logging_Information, "64-Bit Operating System detected."
			strCommand = strSEP_W64_UNCPath
		Else
			objLogging.WriteToFile Logging_Information, "32-Bit Operating System detected."
			strCommand = strSEP_W32_UNCPath
		End If
		
		strCommand = strCommand & "\" & "setup.exe /v""REBOOT=ReallySuppress /passive /l*v " & strLogFullPath & "\" & strMSIInstallLog & ""
	Else
		' alternative UNC path
		strCommand = WScript.Arguments(0) & "\" & "setup.exe /v""REBOOT=ReallySuppress /passive /l*v " & strLogFullPath & "\" & strMSIInstallLog & ""
	End If
	
	objLogging.WriteToFile Logging_Information, "Calling command: " & strCommand
	
	intRet = 0
	
	SetNonZoneChecks False	
	intRet = objWSHShell.Run(strCommand, 0, True)	
	SetNonZoneChecks True
	
	objLogging.WriteToFile Logging_Information, "Return code " & CStr(intRet)
	
	If (intRet = 0) Or (intRet = 3010) Then
		objLogging.WriteToFile Logging_Information, "SEP installed successfully."
		
		' Reboot required			
		If intRet = 3010 Then
			objLogging.WriteToFile Logging_Information, "Installation requires reboot."			
			
			' Notify user to restart
			ShowDeleyedPopup "Installation finished sucessfully, system will reboot.", "Information", 720, 0
			Restart								
		End If

	Else
			ShowDeleyedPopup "Installation failed!" & vbNewLine & _
							"Please contact your IT department.", "Information", 360, 3
			
			objLogging.WriteToFile Logging_Error, "SEP installation failed."
	End If
	
	Set objWSHShell = Nothing
	
	On Error GoTo 0
End Sub

Sub RelinkServer()
	Dim intRet 
	Dim objWSHShell
	Dim objFilesys
		
	intRet = 0
	
	Set objFilesys = CreateObject("Scripting.FileSystemObject")
	Set objWSHShell = WScript.CreateObject("WScript.Shell") 		
	
	SetNonZoneChecks False
	' Copy relink utility to temp directory		
	objFilesys.CopyFile strSEPRelinkFiles, strLogFullPath
	
	' Run relink
	' * VERY IMPORTANT: If you have SEP uninstall password set here add -p <password> after -silent
	intRet = objWSHShell.Run(strLogFullPath & "\SylinkDrop.exe -silent" & strLogFullPath &  "\Sylink.xml", 0, True)

	' Delete uneeded files
	objFilesys.DeleteFile strLogFullPath & "\SylinkDrop.exe"
	objFilesys.DeleteFile strLogFullPath & "\Sylink.xml"

	SetNonZoneChecks True

	Set objWSHShell = Nothing
	Set objFilesys = Nothing
End Sub


Sub StopAndDisableService(strServiceName)	
	Dim objWMIService, colServiceList, objService, errReturnCode
	
	On Error Resume Next 
	
	objLogging.WriteToFile Logging_Information, "Checking the existence of "	& strServiceName & "."
	
	Set objWMIService = GetObject("winmgmts:" & "{impersonationLevel=impersonate}!\\.\root\cimv2")
	Set colServiceList = objWMIService.ExecQuery ("Select * from Win32_Service where Name = '" & _
     					 strServiceName & "'")
    		 
	' If found, loop through all the services matching that name.
	For Each objService In colServiceList
	' If the service is already disabled, don't bother changing it.
		If (objService.StartMode <> "Disabled") Then				
			objLogging.WriteToFile Logging_Information, "Service not disabled. Disabling service."
			errReturnCode = objService.Change( , , , , "Disabled")
			WScript.Sleep 2000			
		Else
			errReturnCode = 0			
		End If
		
		If (errReturnCode = 0) Then		
			objLogging.WriteToFile Logging_Information, "Service disabled."									
			If (objService.State <> "Stopped") Then
				objLogging.WriteToFile Logging_Information, "Service not stopped. Stopping service."
				errReturnCode = objService.StopService()
			End If					
		Else
			'Something went wrong in trying to disable the service.
			objLogging.WriteToFile Logging_Error, "Service could not be disabled. Error code: " & CStr(errReturnCode)
	 	End If	   
	Next
	
	Set objWMIService = Nothing
	Set colServiceList = Nothing
	
    On Error GoTo 0
End Sub

' // *************************************************
' // ** General porpose functions
' // *************************************************

Function Check64Bit()	
	If CheckIfDirExists("C:\Program Files (x86)") Then 
		Check64Bit = True
	Else	
		Check64Bit = False
	End If	
End Function


Function GetEnvironmentVariable(strVar)
	Dim objShell, objEnv 

	GetEnvironmentVariable = ""
	
	On Error Resume Next

	Set objShell = CreateObject("WScript.Shell")
	
	Set objEnv = objShell.Environment("Process")
	
	GetEnvironmentVariable = objEnv(strVar)
	
	Set objShell = Nothing
	Set objEnv = Nothing

	On Error Goto 0
End Function

Function CheckIfDirExists(strDir)
	Dim objFSO
	
	On Error Resume Next
	Err.Clear
	
	Set objFSO = CreateObject("Scripting.FileSystemObject")
	
	If objFSO.FolderExists(strDir) Then
		CheckIfDirExists = True
	Else
		CheckIfDirExists = False
	End If
	
	On Error GoTo 0
	
	Set objFSO = Nothing
End Function

Sub ShowDeleyedPopup(strMessage, strTitle, intTimeout, intType)
	Dim objWSHShell, intWindowType
	
	Set objWSHShell = CreateObject("WScript.Shell")
	
	Select Case CInt(intType)
		Case 0: 
			' Information
			intWindowType = 64
		Case 1: 
			'Exclamation
			intWindowType = 48
		Case 2: 
			'Question
			intWindowType = 32
		Case 3: 
			'Critical
			intWindowType = 16		
	End Select

	objWSHShell.Popup strMessage, intTimeout, strTitle, intWindowType 
	
	Set objWSHShell = Nothing
End Sub

Sub SetNonZoneChecks(bolFlag)		
	On Error Resume Next
	
	Dim objWShell, objEnv
	
	Set objWShell = CreateObject("Wscript.Shell")
	Set objEnv = objWShell.Environment("PROCESS")
	
	If bolFlag = False Then
		objEnv("SEE_MASK_NOZONECHECKS") = 1		
	Else
		objEnv.Remove("SEE_MASK_NOZONECHECKS")
	End If
	
	Set objWShell = Nothing
	Set objEnv = Nothing
	
	On Error GoTo 0
End Sub

Sub Restart
	On Error Resume Next

	Dim colOperatingSystems, objOperatingSystem

	Set colOperatingSystems = GetObject("winmgmts:{(Shutdown)}").ExecQuery("Select * from Win32_OperatingSystem")
 
	For Each objOperatingSystem In colOperatingSystems
	    ObjOperatingSystem.Win32Shutdown(6)
	Next

	On Error GoTo 0
End Sub

' // *************************************************
' // ** Classes 
' // *************************************************

' Global declarations

' FSO Constants
Const FSO_ForAppending = 8 
Const FSO_ForReading = 1
Const FSO_ForWriting = 2

' // ** Logging contants
Const Logging_Warning = 0
Const Logging_Error = 1
Const Logging_Information = 2

Class Logging

	' Private members
	Private m_bolLoggingEnabled
	Private m_LogFile
	Private m_objFSO
	Private m_objLogFile
	Private m_longMaxLogSize
	Private m_bolFileInitilized
    
	'Constructor
    Private Sub Class_Initialize() 
		Set m_objFSO = CreateObject("Scripting.FileSystemObject")
		
		m_bolFileInitilized = False
		m_bolLoggingEnabled = True
    End Sub
	
	' Properties
	Public Property Let LoggingEnabled(bolFlag)
		m_bolLoggingEnabled = bolFlag
	End Property 
	
	Public Property Get LoggingEnabled
		LoggingEnabled = m_bolLoggingEnabled
	End Property 

	Public Sub InitilizeFile(strLogFile, longMaxLogSize)
		On Error Resume Next
		Err.Clear
		
	    m_LogFile = strLogFile
		m_longMaxLogSize = longMaxLogSize
		
		If Not m_objFSO.FileExists(m_LogFile) Then		
            Set m_objLogFile = m_objFSO.CreateTextFile(m_LogFile, True)
		Else
			Set m_objLogFile = m_objFSO.GetFile(m_LogFile)     
	    
			If (m_objLogFile.Size >= m_longMaxLogSize) Then
				Set m_objLogFile = m_objFSO.CreateTextFile(m_LogFile, True)
			Else
				Set m_objLogFile = m_objFSO.OpenTextFile(m_LogFile, FSO_ForAppending, True)
			End If
		End If
		
		If Err.Number = 0 Then m_bolFileInitilized = True
		
		On Error GoTo 0
	End Sub
        
	Public Sub WriteToFile(intEventType, strMessage)	
		Dim strEventType, strEntry
		
		On Error Resume Next
		
		'If not initlized or logging disabled exit sub
		If (Not m_bolFileInitilized) Or _
   		   (Not m_bolLoggingEnabled) Then _
		   Exit Sub

		Select Case intEventType
			Case Logging_Warning
				strEventType = "Warning    "
			Case Logging_Error
				strEventType = "Error      "
			Case Else
				strEventType = "Information"
		End Select		
		
		' Format entry
		strEntry = GetEightDigitDate() & " " & FormatDateTime(Now(), vbLongTime) & " | " & _
				   "Event Type: " & strEventType & " | Message: " & strMessage
		
		m_objLogFile.WriteLine(strEntry)
			
		On Error GoTo 0
	End Sub
	
	Public Function FormatErrorObject(objError)
		Dim strError
		
		On Error Resume Next
		
		strError = "Error Number (decimal)= " & CStr(objError.Number) & _
					" Error Source = " & objError.Source & _
					" Error Description = " & objError.Description
		
		GetLastError = strError
		
		On Error GoTo 0
	End Function
	
	Public Function GetWMILastError
		Dim objWMI_Error, strError
		
		On Error Resume Next
		
		'Instantiate SWbemLastError object.
		Set objWMI_Error = CreateObject("WbemScripting.SWbemLastError")
		
		strError = "Operation = " & objWMI_Error.Operation & _
				   " ParameterInfo = " & objWMI_Error.ParameterInfo & _
		           " ProviderName = " & objWMI_Error.ProviderName
		
		GetWMILastError = strError
		
		On Error GoTo 0
	End Function
	
	Private Function GetEightDigitDate() 
		Dim strDayOfMonth, strMonth, strYear, strEightDigitDate
		
		On Error Resume Next
		
		strDayOfMonth = Right("0" & Day(Date()), 2) 'Gives two-digit day of month.
		strMonth = Right("0" & Month(Date()), 2) 'Gives two-digit month.
		strYear = Year(Date()) 'Gives four digit year.
		
		strEightDigitDate = strYear & ":" & strMonth & ":" & strDayOfMonth 'Concatenates date values to format YYYYMMDD.
		getEightDigitDate = strEightDigitDate 'Done.
		
		On Error GoTo 0
	End Function
	
	'Destructor
    Private Sub Class_Terminate 
		On Error Resume Next
		
		' Flush buffer and close file
		m_objLogFile.Close()
		
        Set m_objFSO = Nothing
        Set m_objLogFile = Nothing
		
		On Error GoTo 0
    End Sub
	
End Class

Class WindowsRegistry
	' Private members
	Private m_objShell
	
	'Constructor
    Private Sub Class_Initialize() 		
		Set m_objShell = CreateObject("WScript.Shell")
    End Sub
	
	Function ReadKey(strKey)
		Dim objKey
		
		On Error Resume Next	
		Err.Clear

		objKey = m_objShell.RegRead(strKey)
			
		On Error Goto 0

		ReadKey = objKey
	End Function

	Function IsKeyExists(strKey)
		Const NO_EXISTING_KEY = "HKEY_NO_EXISTING\Key\"
		Dim strKeyPath, strNoKeyError
		
		strKeyPath = Trim(strKey)
		
		If Right(strKeyPath, 1) <> "\" Then strKeyPath = strKeyPath & "\"
		
		On Error Resume Next
		
		' Get the error description by trying to read a non-existent key
		m_objShell.RegRead NO_EXISTING_KEY
		strNoKeyError = Err.Description
		
		Err.Clear
		
		m_objShell.RegRead strKeyPath
		' Compare the error description with the previous determined sample
		If Replace(Err.Description, strKeyPath, NO_EXISTING_KEY) = strNoKeyError Then
		  IsKeyExists = False
		Else
		  IsKeyExists = True
		End If
			
		On Error Goto 0
	End Function

	Function IsValueExists(strValue)
		Dim strKeyPath
		
		On Error Resume Next
		Err.Clear
		
		strKeyPath = Trim(strValue)
		
		If Right(strKeyPath, 1) = "\" Then	
			' This is a key format, not a value !
			IsValueExists = False
		Else				
			m_objShell.RegRead strKeyPath
			
			' Compare the error description with the previous determined sample
			If Err.Number <> 0 Then		
			  IsValueExists = False			  
			Else				
			  IsValueExists = True			  
			End If	
		End If
		
		On Error Goto 0		
	End Function
	
	'Destructor
    Private Sub Class_Terminate 
		Set m_objShell = Nothing
    End Sub
	
End Class

Class ScriptingFramework
	' Private members
	Private m_objWinRegistry
	Private m_strDebugLevel
	
	'Constructor
    Private Sub Class_Initialize()
		On Error Resume Next
		
		Set m_objWinRegistry = New WindowsRegistry
		m_strDebugLevel = m_objWinRegistry.ReadKey("HKLM\Software\Scripting Framework\Settings\DebugLevel")
		
		On Error GoTo 0 
    End Sub
	
	Public Function GetScriptProperty(strScriptName, strProperty)
		Dim objValue
		
		On Error Resume Next
		
		objValue = m_objWinRegistry.ReadKey("HKLM\Software\Scripting Framework\Scripts\" & strScriptName & "\" & strProperty)
		
		GetScriptProperty = objValue
	End Function
	
	' Properties
	Public Property Get DebugLevel
		DebugLevel = m_strDebugLevel
	End Property 

	'Destructor
    Private Sub Class_Terminate
		Set m_objWinRegistry = Nothing
    End Sub
	
End Class