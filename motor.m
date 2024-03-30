classdef motor < handle
    % Matlab class to control Thorlabs motorized translation/rotation stage It is a 'wrapper' to control Thorlabs devices via the Thorlabs .NET DLLs.

    % Modifications to implement parallel motion/dynamic trigger changing functionality for KDC101
    % Author: Tomas Blaxall
    % University of Salford, Manchester, UK
    % Email: tomas.blaxall@yahoo.co.uk

    % Author: Andriy Chmyrov (Original Author)
    % Helmholtz Zentrum Muenchen, Deutschland
    % Email: andriy.chmyrov@helmholtz-muenchen.de

    % based on a code of Julan A.J. Fells
    % Dept. Engineering Science, University of Oxford, Oxford OX1 3PJ, UK
    % Email: julian.fells@emg.ox.ac.uk (please email issues and bugs)
    % Website: http://wwww.eng.ox.ac.uk/smploadB

    

    %% Properties
    properties (Constant, Hidden) % Declarations - DLL information, Default velocity, Default acceleration, Default polling time, Timeout for settings change, Timeout for motor movements

        % path to DLL files (edit as appropriate)
        KINESISPATHDEFAULT = 'C:\Program Files\Thorlabs\Kinesis\'
        % DLL files to be loaded
        DEVICEMANAGERDLL='Thorlabs.MotionControl.DeviceManagerCLI.dll';
        DEVICEMANAGERCLASSNAME='Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI'
        GENERICMOTORDLL='Thorlabs.MotionControl.GenericMotorCLI.dll';
        GENERICMOTORCLASSNAME='Thorlabs.MotionControl.GenericMotorCLI.GenericMotorCLI';
        DCSERVODLL='Thorlabs.MotionControl.KCube.DCServoCLI.dll';
        DCSERVOCLASSNAME='Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo';
        INTEGSTEPDLL='Thorlabs.MotionControl.IntegratedStepperMotorsCLI.dll'
        INTEGSTEPCLASSNAME='Thorlabs.MotionControl.IntegratedStepperMotorsCLI.IntegratedStepperMotor.CageRotator';
        BRUSHLESSDLL='Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.dll';
        BRUSHLESSCLASSNAME='Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI ';
        PIEZODLL = 'ThorLabs.MotionControl.GenericPiezoCLI.dll';
        PIEZOCLASSNAME = 'ThorLabs.MotionControl.GenericPiezoCLI';

        % Default intitial parameters
        DEFAULTVEL=1;                                                                                                                                  % Default velocity
        DEFAULTACC=1;                                                                                                                                  % Default acceleration
        TPOLLING=100;                                                                                                                                    % Default polling time
        TIMEOUTSETTINGS=3500;                                                                                                                  % Default timeout time for settings change
        TIMEOUTMOVE=50000;                                                                                                                      % Default time out time for motor move

        % Default inital parameters for triggering specifically
        DEFAULTTRIGGERPOLARITY = "TriggerHigh";                                                                                  % "TriggerHigh" or "TriggerLow" (for KDC101)
        DEFAULTTRIGGER1MODE = "OUT  -  At Position Steps (Both)";                                                   % Refer to Enumeration of configparams jpeg for these or to setupObjects function comments (for KDC101)
        DEFAULTTRIGGER2MODE = "OUT  -  In Motion";
        DEFAULTTRIGGERATPOSITION = 2;
        % text2num_triggerDict = containers.Map( {'disabled', 'in_gpi', 'in_rel', 'in_abs', 'in_home', 'in_stop', 'out_gpo', 'out_motion', 'out_maxvel', 'out_fwdpos', 'out_revpos', 'out_bothpos', 'out_fwdlim', 'out_revlim', 'out_bothlim' }, { 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 } );
        % num2text_triggerDict = containers.Map( { 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 }, { 'disabled', 'in_gpi', 'in_rel', 'in_abs', 'in_home', 'in_stop', 'out_gpo', 'out_motion', 'out_maxvel', 'out_fwdpos', 'out_revpos', 'out_bothpos', 'out_fwdlim', 'out_revlim', 'out_bothlim' } );

    end

    properties % Easily accessible properties for inside of MATLAB wrapper - serialnumber, controllername, controllerdescription, stagename, acclimit, vellimit
        serialnumber;                                                                                                                                       % Device serial number
        controllername;                                                                                                                                   % Controller Name
        controllerdescription                                                                                                                           % Controller Description
        stagename;                                                                                                                                           % Stage Name
        acclimit;                                                                                                                                                 % Acceleration limit
        vellimit;                                                                                                                                                  % Velocity limit
        backlash;
        triggersCurrent;                                                                                                                                    % Trigger objects for configuration parameters and parameter parameters (paramparams are where it will be triggered; configParams for polarity & mode)
        triggerRefs;                                                                                                                                            % Reference objects that are impossible to set without getting a copy of the class object contained inside of the dlls - this was hard to figure out how to fix
    end

    properties (Dependent)
        isconnected;                 % Flag set if device connected
        position;                    % Position
        maxvelocity;                 % Maximum velocity limit
        minvelocity;                 % Minimum velocity limit
        acceleration;                % Acceleration
    end

    properties (Hidden)
        % These are properties within the .NET environment.
        deviceNET;                   % Device object within .NET
        motorSettingsNET;            % motorSettings within .NET
        currentDeviceSettingsNET;    % currentDeviceSetings within .NET
        deviceInfoNET;               % deviceInfo within .NET
        prefix;                      % prefix of the serial number
        channel;                     % channels for multichannel controller
        controller;                  % controller of synchronous functionality (BBD30X only).
        initialized = false;         % initialization flag
        triggerObjectsInit = false; % flag for trigger object initialisation
        triggerConfigInit = false;
    end

    %% P U B L I C     M E T H O D S - h = motor(), h.delete()
    methods

        % =================================================================

        function h = motor() % Constructor - Instantiate motor object, load dlls
            motor.loaddlls; % Load DLLs (if not already loaded)
        end

        % =================================================================
        
        function delete(h) % Destructor
            if ~isempty(h.deviceNET) && h.deviceNET.IsConnected()
                try
                    disconnect(h);
                catch
                end
            end
        end

        % =================================================================

    end

    %% S E A L E D    M E T H O D S - INTERFACE IMPLEMENTATION
    methods (Sealed)
        %% General utility methods - connect(h,serialNo), disconnect(h), updatestatus(h), reset(h,serialNo), enable(hc,hnum), disable(h,chnum), home(h,chnum), res=ishomed(h,chnum), res=getstatus(h,chnum), cleardeviceexceptions(h,chnum)

        function connect(h,serialNo) % Connect device
            h.listdevices();    % Use this call to build a device list in case not invoked beforehand
            if ~h.initialized % if device isnt initialised then do the following
                if isnumeric(serialNo) && isscalar(serialNo)
                    serialNo = int2str(serialNo);
                end
                h.prefix = int32(str2double(serialNo(1:end-6))); % Convert the string input of the serial number to an int32 type, and strip it of all but first two numbers
                switch(h.prefix) % Switch case that checks the prefix and assigns deviceNET property to class object
                    case Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix  % 27 - Serial number corresponds to a PRM1Z8 or ZB718
                        h.deviceNET = Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.CreateKCubeDCServo(serialNo);
                    case Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix % 55 - Serial number corresponds to a K10CR1
                        h.deviceNET = Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.CreateCageRotator(serialNo);
                    case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103 % 103 - Serial number corresponds to BBD30X type devices
                        h.deviceNET = Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.CreateBenchtopBrushlessMotor(serialNo);
                    otherwise % Serial number is not handled as a case
                        error('Stage not recognised');
                end

                try % Clear device exceptions via .NET interface
                    h.deviceNET.ClearDeviceExceptions();    
                catch exception %#ok<NASGU>
                    error('Exception caught when trying to clear device exceptions')
                end

                h.deviceNET.Connect(serialNo);          % Connect to device via .NET interface using the dll
                switch(h.prefix) % check what the prefix of the connected motor is and handle it casewise
                    case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix, Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                        try % Get deviceInfo via .NET interface
                            h.deviceInfoNET = h.deviceNET.GetDeviceInfo();                    
                            if ~h.deviceNET.IsSettingsInitialized % Wait for IsSettingsInitialized via .NET interface
                                h.deviceNET.WaitForSettingsInitialized(h.TIMEOUTSETTINGS);
                            end
                            if ~h.deviceNET.IsSettingsInitialized % Cannot initialise device
                                error(['Unable to initialise device ',char(serialNo)]);
                            end
                            h.deviceNET.StartPolling(h.TPOLLING);   % Start polling via .NET interface
                            if ~h.deviceNET.IsEnabled % Check if the device is enabled and do so if necessary
                                pause(0.1);
                                h.deviceNET.EnableDevice();
                                pause(0.1);
                            end
                            h.motorSettingsNET = h.deviceNET.LoadMotorConfiguration(serialNo); % Load motorSettings via .NET interface
                            h.stagename = char(h.motorSettingsNET.DeviceSettingsName);    % update stagename
                            h.currentDeviceSettingsNET = h.deviceNET.MotorDeviceSettings;     % Get currentDeviceSettings via .NET interface
                            h.acclimit = System.Decimal.ToDouble(h.currentDeviceSettingsNET.Physical.MaxAccnUnit);
                            h.vellimit = System.Decimal.ToDouble(h.currentDeviceSettingsNET.Physical.MaxVelUnit);
                            %MotDir=Thorlabs.MotionControl.GenericMotorCLI.Settings.RotationDirections.Forwards; % MotDir is enumeration for 'forwards'
                            %h.currentDeviceSettingsNET.Rotation.RotationDirection=MotDir;   % Set motor direction to be 'forwards#
                        catch % Cannot initialise device
                            error(['Unable to initialise device ',char(serialNo)]);
                        end

                    case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103

                        % Reflection to get motherboard configuration, find devicemanagerCLI object and perform reflection on it to get name of UseDeviceSettingsObject
                        assemblies = System.AppDomain.CurrentDomain.GetAssemblies;
                        asmname = 'Thorlabs.MotionControl.DeviceManagerCLI';
                        asmidx = find(arrayfun(@(n) strncmpi(char(assemblies.Get(n-1).FullName), asmname, length(asmname)), 1:assemblies.Length));
                        settings_enum  = assemblies.Get(asmidx-1).GetType('Thorlabs.MotionControl.DeviceManagerCLI.DeviceConfiguration+DeviceSettingsUseOptionType');
                        settings_enumName = 'UseDeviceSettings';
                        settings_enumIndx = find(arrayfun(@(n) strncmpi(char(settings_enum.GetEnumValues.Get(n-1)), settings_enumName, length(settings_enumName)), 1:settings_enum.GetEnumValues.GetLength(0)));
                        h.deviceNET.GetMotherboardConfiguration(serialNo,settings_enum.GetEnumValues.Get(settings_enumIndx-1));
                        % Outcome of reflection process

                        h.deviceInfoNET = h.deviceNET.GetDeviceInfo();
                        h.controller = h.deviceNET.GetSyncController;

                        for km = 1:double(h.deviceInfoNET.NumChannels)
                            h.channel{km} = h.deviceNET.GetChannel(km);
                            try
                                h.channel{km}.Connect(serialNo);
                                if(~h.channel{km}.IsSettingsInitialized)
                                    h.channel{km}.WaitForSettingsInitialized(3000);
                                end
                            catch Exception %#ok<NASGU>
                                disp("Settings failed to initialize");
                            end

                            h.motorSettingsNET{km} = h.channel{km}.LoadMotorConfiguration(h.channel{km}.DeviceID); % Load motorSettings via .NET interface
                            h.channel{km}.StartPolling(h.TPOLLING);   % Start polling via .NET interface
                            pause(0.25);
                            h.stagename{km} = char(h.motorSettingsNET{km}.DeviceSettingsName);    % update stagename
                            h.currentDeviceSettingsNET{km} = h.channel{km}.MotorDeviceSettings();     % Get currentDeviceSettings via .NET interface
                            h.acclimit(km) = System.Decimal.ToDouble(h.currentDeviceSettingsNET{km}.Physical.MaxAccnUnit);
                            h.vellimit(km) = System.Decimal.ToDouble(h.currentDeviceSettingsNET{km}.Physical.MaxVelUnit);
                        end
                end

            else % If the device is already connected and initialised flag is true
                error('Device is already connected.')
            end

            % After checking if initialised and acting accordingly, populate class objects serialnumber, controllername, controllerdescription
            h.serialnumber   = char(h.deviceNET.DeviceID);        % update serial number
            h.controllername = char(h.deviceInfoNET.Name);        % update controller name
            h.controllerdescription = char(h.deviceInfoNET.Description);  % update controller description
            fprintf('%s with S/N %s is connected successfully!\n',h.controllerdescription,h.serialnumber);
            pause(0.25); % wait (just in case) before getting the objects
            if(h.triggerObjectsInit == false)
                setupObjects(h);
                if(h.triggerConfigInit == false)
                    error(['expected config to be initialised on return S/N:%s',h.serialnumber]);
                end
            end
            h.initialized = true; % Set initaialised flag to true, so that init function won't replay if re-called

        end

        % =================================================================

        function disconnect(h) % Disconnect device

            if h.isconnected

                try % figure out what motor we are connecting to
                    switch(h.prefix)
                        case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix, Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                            h.deviceNET.StopPolling();  % Stop polling device via .NET interface
                            h.deviceNET.Disconnect();   % Disconnect device via .NET interface
                        case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103 % Serial number corresponds to a BBD302
                            for km = 1:double(h.deviceInfoNET.NumChannels)
                                h.channel{km}.StopPolling();
                            end
                            h.deviceNET.ShutDown; % applies to all Benchtop devices
                    end
                catch Exception
                    error(['Unable to disconnect device',h.serialnumber]);
                end % end of try statement
                fprintf('%s with S/N %s is disconnected successfully!\n',h.controllerdescription,h.serialnumber);

            else % Cannot disconnect because device not connected
                error('Device not connected.')
            end

            h.initialized = false; % Finally set initialised flag to false
        end

        % =================================================================

        function updatestatus(h) % Update params in class from device - isconnected, serialnumber, controllername, controllerdescription, stagename, acceleration, maxvelocity, minvelocity, position
            h.isconnected = logical(h.deviceNET.IsConnected());                                                                % update isconncted flag
            h.serialnumber = char(h.deviceNET.DeviceID);                                                                           % update serial number
            h.controllername = char(h.deviceInfoNET.Name);                                                                     % update controleller name
            h.controllerdescription = char(h.deviceInfoNET.Description);                                                 % update controller description
            h.stagename = char(h.motorSettingsNET.DeviceSettingsName);                                            % update stagename
            velocityparams = h.deviceNET.GetVelocityParams();                                                                 % update velocity parameter
            h.acceleration = System.Decimal.ToDouble(velocityparams.Acceleration);                          % update acceleration parameter
            h.maxvelocity = System.Decimal.ToDouble(velocityparams.MaxVelocity);                           % update max velocit parameter
            h.minvelocity = System.Decimal.ToDouble(velocityparams.MinVelocity);                            % update Min velocity parameter
            h.position = System.Decimal.ToDouble(h.deviceNET.Position);                                               % Read current device position
        end %end of update status

        % =================================================================

        function reset(h,serialNo) % Reset device

            if nargin < 2 % if serial number isn't provided then just get it from the properties of the class
                serialNo = h.serialnumber;
            end

            switch(h.prefix) % change methods based on which motor is connected
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix, Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    h.deviceNET.ClearDeviceExceptions();  % Clear exceptions via .NET interface
                    h.deviceNET.ResetConnection(serialNo) % Reset connection via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        h.channel{km}.ClearDeviceExceptions();  % Clear exceptions via .NET interface
                        h.channel{km}.ResetConnection(serialNo) % Reset connection via .NET interface
                    end
            end % end of switch statement

        end

        % =================================================================

        function enable(h,chnum) % Enable device or channel
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix, Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    if ~h.deviceNET.IsEnabled
                        h.deviceNET.EnableDevice();
                        pause(0.5);
                    end
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103 % for multi-axes controller we need to enable channels
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        if ~h.channel{km}.IsEnabled
                            h.channel{km}.EnableDevice();
                            pause(0.5); % Needs a delay to give time for the device to be enabled
                        end
                    end
            end
        end

        % =================================================================

        function disable(h,chnum) % Disable device or channel
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix, Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix} % if KCube driver or Cage Rotator
                    if h.deviceNET.IsEnabled
                        h.deviceNET.DisableDevice();
                        pause(0.1);
                    end

                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103 % Mutli-channel driver
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist % For all channels in channel list, enable them
                        if h.channel{km}.IsEnabled
                            h.channel{km}.DisableDevice();
                            pause(0.1);
                        end
                    end

            end % End of Switch Statement
        end

        % =================================================================

        function home(h,chnum) % Home device (must be done before any device move)
            switch(h.prefix) % Switch for specific motor drivers
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix, Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix} % If KCube motor or Cage rotator
                    if ~h.deviceNET.NeedsHoming()
                        fprintf(2,'Device does not necessarily needs homing, gonna do it anyway! #menace2society\n');
                    end
                    workDone = h.deviceNET.InitializeWaitHandler();                                                             % Initialise Waithandler for timeout
                    h.deviceNET.Home(workDone);                                                                                            % Home devce via .NET interface
                    h.deviceNET.Wait(h.TIMEOUTMOVE);                                                                                  % Wait for move to finish
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        if ~h.channel{km}.IsEnabled()
                            error('Channel %d is not enabled! Please enable it first before homing.',km)
                        end
                        if ~h.channel{km}.NeedsHoming()
                            fprintf(2,'Device does not necessarily needs homing!\n');
                        end
                        workDone{km} = h.channel{km}.InitializeWaitHandler();                                             % #ok<AGROW> % Initialise Waithandler for timeout
                        h.channel{km}.Home(workDone{km});                                                                            % Home devce via .NET interface
                        h.channel{km}.Wait(h.TIMEOUTMOVE);                                                                          % Wait for move to finish
                    end
            end
        end

        % =================================================================

        function res = ishomed(h,chnum) % Check if the device or the channel is homed

            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix, Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix} % KCube or Cage Rotator
                    if ~h.deviceNET.NeedsHoming()
                        %fprintf(2, 'Device does not necessarily needs homing!\n');
                    end
                    status = h.deviceNET.Status();
                    res = status.IsHomed;
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103 % multi-channel controller
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        chstatus = h.channel{km}.Status();  % Chech if the channel needs homing
                        if nargin == 2
                            res = chstatus.IsHomed;
                        else
                            res(km) = chstatus.IsHomed;
                        end
                    end
            end % End of switch statement

        end

        % =================================================================

        function res = getstatus(h,chnum)
            switch(h.prefix)
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        chstatus = h.channel{km}.Status;  % Check if the channel needs homing
                        if nargin == 2
                            res = chstatus;
                        elseif nargin == 1
                            res{km} = chstatus;
                        end
                    end
            end
        end

        % =================================================================

        function cleardeviceexceptions(h,chnum)
            switch(h.prefix)
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        h.channel{km}.ClearDeviceExceptions;
                    end
            end
        end



        %% Motion methods - moveto(h,position), movetopar(h,position), moverel_deviceunit(h,noclicks), movecont(h,varargin), stop(h,chnum)
        
        function moveto(h,position) % Move to absolute position
            switch(h.prefix) % Switch for Motor Type
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix, Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    try
                        workDone=h.deviceNET.InitializeWaitHandler(); % Initialise Waithandler for timeout
                        h.deviceNET.MoveTo(position, workDone);       % Move devce to position via .NET interface
                        h.deviceNET.Wait(h.TIMEOUTMOVE);              % Wait for move to finish
                        % updatestatus(h); % If having problems, comment this out, it's to update after moving
                    catch % Device failed to move
                        error(['Unable to Move device ',h.serialnumber,' to ',num2str(position)]);
                    end
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103

                    if length(position) ~= h.deviceInfoNET.NumChannels
                        error([int2str(h.deviceInfoNET.NumChannels) ' coordinates expected for the device ',h.controllername,' with serial number ',h.serialnumber,'!']);
                    end

                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        workDone{km} = h.channel{km}.InitializeWaitHandler(); % #ok<AGROW> % Initialise Waithandler for timeout for each channel
                    end

                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        h.channel{km}.MoveTo(position(km),workDone{km});
                    end

                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        h.channel{km}.Wait(h.TIMEOUTMOVE);              % Wait for move to finish
                    end

            end % End of switch statement
        end

        % =================================================================

        function movetopar(h,position)     % Move to absolute position
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    try
                        workDone=h.deviceNET.InitializeWaitHandler(); % Initialise Waithandler for timeout
                        h.deviceNET.MoveTo(position, workDone);       % Move devce to position via .NET interface
                    catch % Device faile to move
                        error(['Unable to Move device ',h.serialnumber,' to ',num2str(position)]);
                    end
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if length(position) ~= h.deviceInfoNET.NumChannels
                        error([int2str(h.deviceInfoNET.NumChannels) ' coordinates expected for the device ',h.controllername,' with serial number ',h.serialnumber,'!']);
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        workDone{km} = h.channel{km}.InitializeWaitHandler(); %#ok<AGROW> % Initialise Waithandler for timeout
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        h.channel{km}.MoveTo(position(km),workDone{km});
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        h.channel{km}.Wait(h.TIMEOUTMOVE);              % Wait for move to finish
                    end
            end
        end

        % =================================================================

        function moverel_deviceunit(h, noclicks)  % Move relative by a number of device clicks (noclicks)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    if noclicks < 0
                        % if noclicks is negative, move device in backwards direction
                        motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Backward;
                        noclicks = abs(noclicks);
                    else
                        % if noclicks is positive, move device in forwards direction
                        motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Forward;
                    end
                    % Perform relative device move via .NET interface
                    h.deviceNET.MoveRelative_DeviceUnit(motordirection,noclicks,h.TIMEOUTMOVE);
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if length(noclicks) ~= h.deviceInfoNET.NumChannels
                        error([int2str(h.deviceInfoNET.NumChannels) ' clicks expected for the device ',h.controllername,' with serial number ',h.serialnumber,'!']);
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        if noclicks(km) < 0
                            % if noclicks is negative, move device in backwards direction
                            motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Backward;
                        else
                            % if noclicks is positive, move device in forwards direction
                            motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Forward;
                        end
                        noclicks_ = abs(noclicks(km));
                        h.channel{km}.MoveRelative_DeviceUnit(motordirection,noclicks_,h.TIMEOUTMOVE);
                    end
            end
        end

        % =================================================================
        
        function movecont(h, varargin)  % Set motor to move continuously
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    if (nargin>1) && (varargin{1})      % if parameter given (e.g. 1) move backwards
                        motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Backward;
                    else                                % if no parametr given move forwards
                        motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Forward;
                    end
                    h.deviceNET.MoveContinuous(motordirection); % Set motor into continous move via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    % !!! DIFFERENT SYNTAX !!!
                    % [1,1] - cont move forward, [-1,-1] - cont move backwards
                    if length(varargin{1}) ~= h.deviceInfoNET.NumChannels
                        error([int2str(h.deviceInfoNET.NumChannels) ' directions expected for the device ',h.controllername,' with serial number ',h.serialnumber,'!']);
                    end
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        if (varargin{1} == 1)      % move forwards
                            motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Forward;
                        elseif (varargin{1} == -1) % move backwards
                            motordirection = Thorlabs.MotionControl.GenericMotorCLI.MotorDirection.Backward;
                        end
                        h.channel{km}.MoveContinuous(motordirection); % Set motor into continous move via .NET interface
                    end
            end
        end

        % =================================================================

        function stop(h,chnum) % Stop the motor moving (needed if set motor to continous)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    h.deviceNET.Stop(h.TIMEOUTMOVE); % Stop motor movement via.NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    if nargin == 2
                        chlist = chnum;
                    else
                        chlist = 1:double(h.deviceInfoNET.NumChannels);
                    end
                    for km = chlist
                        h.controller.Stop(uint32(km));
                    end
            end
        end



        %% Change Attribute/Behaviour of Motor Methods - setvelocity(h,varargin), setbacklash(h,backlash), getbacklash(h)

        function setvelocity(h, varargin)  % Set velocity and acceleration parameters
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    switch(nargin)
                        case 1  % If no parameters specified, set both velocity and acceleration to default values
                            velpars.MaxVelocity  = h.DEFAULTVEL;
                            velpars.Acceleration = h.DEFAULTACC;
                        case 2  % If just one parameter, set the velocity
                            velpars.MaxVelocity  = varargin{1};
                        case 3  % If two parameters, set both velocitu and acceleration
                            velpars.MaxVelocity  = varargin{1};  % Set velocity parameter via .NET interface
                            velpars.Acceleration = varargin{2}; % Set acceleration parameter via .NET interface
                    end
                    if System.Decimal.ToDouble(velpars.MaxVelocity)>25  % Allow velocity to be outside range, but issue warning
                        warning('Velocity >25 deg/sec outside specification')
                    end
                    if System.Decimal.ToDouble(velpars.Acceleration)>25 % Allow acceleration to be outside range, but issue warning
                        warning('Acceleration >25 deg/sec2 outside specification')
                    end
                    h.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        velpars = h.channel{km}.GetVelocityParams(); % Get existing velocity and acceleration parameters
                        switch(nargin)
                            case 1  % If no parameters specified, set both velocity and acceleration to default values
                                velpars.MaxVelocity = h.DEFAULTVEL;
                                velpars.Acceleration = h.DEFAULTACC;
                            case 2  % If just one parameter, set the velocity
                                par1 = varargin{1};
                                velpars.MaxVelocity = par1(km);
                            case 3  % If two parameters, set both velocitu and acceleration
                                par1 = varargin{1};
                                par2 = varargin{2};
                                velpars.MaxVelocity  = par1(km);  % Set velocity parameter via .NET interface
                                velpars.Acceleration = par2(km); % Set acceleration parameter via .NET interface
                        end
                        if System.Decimal.ToDouble(velpars.MaxVelocity)>250  % Allow velocity to be outside range, but issue warning
                            warning('Velocity >250 mm/sec outside specification')
                        end
                        if System.Decimal.ToDouble(velpars.Acceleration)>2000 % Allow acceleration to be outside range, but issue warning
                            warning('Acceleration >2000 mm/sec2 outside specification')
                        end
                        h.channel{km}.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                    end
            end
        end

        % =================================================================

        function setbacklash(h,backlash) % Set the backlash of the motor
            if (backlash < 0.001)
                error('Backlash limit exceeded')
            else
                h.deviceNET.setbacklash(Backlash);
            end
            Bl = h.deviceNET.GetBacklash();
            h.backlash=(System.Decimal.ToDouble(Bl));
        end % end of set backalash

        % =================================================================

        function getbacklash(h)
            try
                Bl=h.deviceNET.GetBacklash();
                disp(System.Decimal.ToDouble(Bl));
                h.backlash=(System.Decimal.ToDouble(Bl));
            catch
                error(['error getting backlash S/N:%s',h.serialnumber]);
            end
        end



        %% Trigger related methods - updateDeviceConfigTriggers(h), updateMatlabConfigTriggers(h), initTriggers(h)

        function updateDeviceConfigTriggers(h)                                                                                         % sends the trigger config object inside of the matlab wrapper over to the device
            try
                h.deviceNET.SetTriggerConfigParams(h.triggersCurrent.config);
            catch % updating trigger config params on device failed
                error(['Updating trigger config params on device failed S/N:%s',h.serialnumber]);
            end
            if(h.triggerConfigInit == false)
                h.triggerConfigInit = true;
            end
        end

        % =================================================================

        function updateMatlabConfigTriggers(h)                                                                                         % gets the trigger config object from the device and brings it over to matlab
            try
                fprintf('Motor w/ S/N   %s Update Triggers Function Called%s\n',h.serialnumber);
                h.triggersCurrent.config = h.deviceNET.GetTriggerConfigParams();
                h.triggersCurrent.params = h.deviceNET.GetTriggerParamsParams();
            catch
                error(['Updating trigger config params on matlab side failed S/N:%s',h.serialnumber]);
            end
        end

        % =================================================================

        function initTriggers(h)                                                                                                                        % Set trigger states upon connection, modify as necessary or implement more robust way of handling changes
            try
                updateTriggersFlag = false;
                h.updateMatlabConfigTriggers(h);
                if(h.prefix ~= Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix) % error out since it's not the motor driver we expect and IDK what consequences this being the case might hold
                    error("Not the KCube motor driver, you will have to look at how I implemented all of this (Tomas Blaxall), and change it around for your purposes, sorry!");
                else % it's the right motor
                    % check default trigger config settings, set if needed
                    if(string(h.triggersCurrent.config.Trigger1Mode) ~= h.DEFAULTTRIGGER1MODE)    % If Trigger1Mode is not equal to the default Trigger1Mode
                        updateTriggersFlag = true;
                        h.triggersCurrent.Trigger1Mode = h.triggerRefs.mode.out.bothpos;                      % set the current trigger1mode to desired trigger1mode
                        fprintf('Motor w/ S/N %s Had Trigger1Mode set to %s\n',h.serialnumber, h.DEFAULTTRIGGER1MODE);
                    end
                    if(string(h.triggersCurrent.config.Trigger2Mode) ~= h.DEFAULTTRIGGER2MODE)    % If Trigger2Mode is not equal to the default Trigger2Mode
                        updateTriggersFlag = true;
                        h.triggersCurrent.Trigger2Mode = h.triggerRefs.mode.out.motion;                      % set the current trigger1mode to desired trigger1mode
                        fprintf('Motor w/ S/N %s Had Trigger2Mode set to %s\n',h.serialnumber, h.DEFAULTTRIGGER2MODE);
                    end
                    if(string(h.triggersCurrent.config.Trigger1Polarity) ~= "TriggerHigh" || string(h.triggersCurrent.config.Trigger2Polarity) ~= "TriggerHigh" ) % If polarity not set to high
                        updateTriggersFlag = true;
                        fprintf('Motor w/ S/N   %s output 1: %s    output 2:%s\n',h.serialnumber, h.triggersCurrent.config.Trigger1Polarity, h.triggersCurrent.config.Trigger2Polarity);
                        h.triggersCurrent.config.Trigger1Polarity = h.triggerRefs.polarity.TriggerHigh;
                        h.triggersCurrent.config.Trigger2Polarity = h.triggerRefs.polarity.TriggerHigh;
                        fprintf('Changed output to:   %s output 1: %s    output 2:%s\n', h.triggersCurrent.config.Trigger1Polarity, h.triggersCurrent.config.Trigger2Polarity);
                    end
                end
                if(updateTriggersFlag == true) % if anything in the above if statements was triggered, meaning that they were set incorrectly, then call the setter function for actually updating the stage
                    h.updateDeviceConfigTriggers(h)
                    h.triggerConfigInit = true;
                end
            catch
                error(['checking triggers failed S/N:%s',h.serialnumber]);
            end
        end

        % =================================================================

        function setDeviceTriggerParams(h, triggerParams)
            disp('this still needs doing');
        end
       

        %% Strange methods - SetupObjects(h)

        function setupObjects(h) % Setup the trigger reference objects to be used when setting the trigger settings
            if(h.triggerObjectsInit == 1 || h.triggerConfigInit == 1) % if function has been called but objects already initialised then error out
                error('tried to init trigger objects when already initiated');
            else % if not then populate the triggerObjects inside of the motor
                updateMatlabConfigTriggers(h);
            end
            switch(h.prefix) % Motor type switch statement based on SN prefix
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix} % if KCube ,Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix
                    try  % Body of code (only coded for KCube motors)

                        % Reflection for enumerators to set reference objects, first the trigger polarity
                        r_Trig1Polarity = GetType(h.triggersCurrent.config.Trigger1Polarity); % Reflect the triggerPolarity 1 type from inside of cpars
                        refobj_triggerPolarity = r_Trig1Polarity.GetEnumValues; % Get enumerator from trigger 1 property 
                        % Reflection for trigger mode
                        r_Trig1Mode = GetType(h.triggersCurrent.config.Trigger1Mode); % Reflect the triggerPolarity 1 type from inside of cpars
                        refobj_triggerMode = r_Trig1Mode.GetEnumValues; % Get enumerator from trigger 1 property 
                        % End of reflection

                        
                        % Set reference objects to temporary variables for no reason, this could be done directly to class props, or instead with a for loop and a list etc, but this keeps all options readable in the wrapper
                        % Set reference objects for trigger Polarity (Trigger#Polarity)
                        refobj_triggerHigh = refobj_triggerPolarity(int32(1));                                                  % "TriggerHigh"
                        refobj_triggerLow = refobj_triggerPolarity(int32(2));                                                   % "TriggerLow"
                        % Assign objects to the properties inside of the main motor class instance
                        h.triggerRefs.polarity.TriggerHigh = refobj_triggerHigh; 
                        h.triggerRefs.polarity.TriggerLow = refobj_triggerLow;
                        % Trash removal
                        clear refobj_triggerLow refobj_triggerHigh r_Trig1Polarity refobj_triggerPolarity r_Trig1Polarity r_Trig1Mode
                        % End of settings reference objects config polarity


                       % Set reference objects for trigger Mode (Trigger#Mode)                                                                                                                                                                                                                                                             :     2xspaces pre/post dash
                        refobj_disabled = refobj_triggerMode(int32(1));                                                           % Disabled                                                                                                                                                                                                :     "Disabled"
                        refobj_i_gpi = refobj_triggerMode(int32(2));                                                                 % Input trigger for general purpose read through status bits using the LLGetStatusBits method (see Thorlabs Docs)        :     "IN  -  GPI"
                        refobj_i_relativemove = refobj_triggerMode(int32(3));                                               % Input trigger for performing a move to a fixed relative amount when triggered                                                                     :     "IN  -  Relative Move"
                        refobj_i_absolutemove = refobj_triggerMode(int32(4));                                             % Input trigger for performing move to specified position when triggered                                                                                  :     "IN  -  Absolute Move"
                        refobj_i_home = refobj_triggerMode(int32(5));                                                            % Input trigger for homing when triggered                                                                                                                                         :     "IN - Home"
                        refobj_i_stop = refobj_triggerMode(int32(6));                                                               % Input trigger to stop no matter what when triggered                                                                                                                   :     "IN  -  Stop"
                        refobj_o_gpo = refobj_triggerMode(int32(7));                                                               % General purpose logic output (set using the LLSetGetDigOPs method). 0x0000000A                                                            :     "OUT  -  GPO"
                        refobj_o_inmotion = refobj_triggerMode(int32(8));                                                     % Output trigger (level) for when driver is in motion 0x0000000B                                                                                                 :     "OUT  -  In Motion"
                        refobj_o_maxvelocity = refobj_triggerMode(int32(9));                                                % Output trigger (level) for when driver is moving at its max velocity 0x0000000C                                                                    :     "OUT  -  At Max Velocity"
                        % Positional output triggers! Very useful, verbose explanation below
                        refobj_o_atposfwd = refobj_triggerMode(int32(10));                                                  % Output trigger (pulsed) for when at position and moving in positive direction 0x0000000D                                                 :     "OUT  -  At Position Steps (Fwd)"
                        refobj_o_atposrev = refobj_triggerMode(int32(11));                                                   % Output trigger (pulsed) for when at position and moving in negative direction 0x0000000E                                                 :     "OUT  -  At Position Steps (Rev)"
                        refobj_o_atposboth = refobj_triggerMode(int32(12));                                                 % Output trigger (pulsed) for when at position and moving in either direction 0x0000000F                                                     :     "OUT  -  At Position Steps (Both)"
                        % Verbose explanation of triggers
                        % This hooks in with the paramparams, defintions etc, so these triggers provide a pulsed output at an exact location with very low latency
                        % as low as 1 microsecond, the trigger activates first at the specified location in paramparams and then after moving a distance from that initial
                        % triggering point equal to the interval, the interval does not refer to the interval of the pulse but it instead refers to the interval between these
                        % two distinct triggering events. Furthermore, if TriggerPolarity == HIGH : 5V w/ rising edge & if TriggerPolarity == LOW : 0V w/ trailing edge
                        refobj_o_atfwdlimit = refobj_triggerMode(int32(13));                                                 % Output trigger (untested) at forward limit of axis 0x000000010                                                                                                  :     "OUT  -  At Forward Limit"
                        refobj_o_atrevlimit = refobj_triggerMode(int32(14));                                                  % Output trigger (untested) at reverse limit of axis 0x000000011                                                                                                   :     "OUT  -  At Reverse Limit"
                        refobj_o_atlimitboth = refobj_triggerMode(int32(15));                                               % Output trigger (untested) at both limits of axis 0x000000012                                                                                                      :     "OUT  -  At Limit"
                       

                        % set actual motor properties
                        h.triggerRefs.mode.disabled = refobj_disabled;
                        h.triggerRefs.mode.in.gpi = refobj_i_gpi;
                        h.triggerRefs.mode.in.rel = refobj_i_relativemove;
                        h.triggerRefs.mode.in.abs = refobj_i_absolutemove;
                        h.triggerRefs.mode.in.home = refobj_i_home;
                        h.triggerRefs.mode.in.stop = refobj_i_stop;
                        h.triggerRefs.mode.out.gpo = refobj_o_gpo;
                        h.triggerRefs.mode.out.motion = refobj_o_inmotion;
                        h.triggerRefs.mode.out.maxvel = refobj_o_maxvelocity;
                        h.triggerRefs.mode.out.fwdpos = refobj_o_atposfwd;
                        h.triggerRefs.mode.out.revpos = refobj_o_atposrev;
                        h.triggerRefs.mode.out.bothpos = refobj_o_atposboth;
                        h.triggerRefs.mode.out.fwdlim = refobj_o_atfwdlimit;
                        h.triggerRefs.mode.out.revlim = refobj_o_atrevlimit;
                        h.triggerRefs.mode.out.bothlim = refobj_o_atlimitboth;
                        % Trash removal
                        clear refobj_disabled refobj_i_gpi refobj_i_relativemove refobj_i_absolutemove refobj_i_home refobj_i_stop refobj_o_gpo refobj_o_inmotion refobj_o_maxvelocity refobj_o_atposfwd refobj_o_atposrev refobj_o_atposboth refobj_o_atfwdlimit refobj_o_atrevlimit refobj_o_atlimitboth refobj_triggerPolarity
                        % End of setting ref objects config mode
                        fprintf('Motor w/ S/N   Has just had the motor object reference objects set%s \n',h.serialnumber);
                        h.triggerObjectsInit = true;

                        % Set reference objects for trigger Params, at least the non-numeric ones okay so, we don't need to set up any other reference objects at this point, but instead, I ran into another slight concern, 
                        % upon constructing the TriggerParamParams object using triggerPars = Thorlabs.MotionControl.GenericMotorCLI.ControlParameters.KCubeTriggerParamsParameters() I changed the InternalRev 
                        % parameter to a System.Decimal since that's what the class showed up as in the workspace, but the untouched parameter TriggerCountRev shows up as an int32, so, when it comes to actually
                        % changing these variables, I need to use the class() command on the object after using GetTriggerParamParams command just to be sure, but luckily there is still other work to do.
                        
                    catch % Getting the trigger paramaters failed
                        error(['Unable to assign config params',h.serialnumber]);
                    end

            end
        end
        %% End of Strange Methods
    end % methods (Sealed)




    %% M E T H O D S - DEPENDENT, REQUIRE SET/GET

    methods

        % =================================================================

        function set.acceleration(h, val)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    % check physical limits
                    if val > h.acclimit
                        error('Requested acceleration is higher than the physical limit, which is %.2f',h.acclimit);
                    end
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    velpars.Acceleration = val;
                    h.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        % check physical limits
                        if val(km) > h.acclimit(km)
                            error('Requested acceleration is higher than the physical limit for Ch%d, which is %.2f',km,h.acclimit(km));
                        end
                        velpars = h.channel{km}.GetVelocityParams(); % Get existing velocity and acceleration parameters
                        velpars.Acceleration = val(km);
                        h.channel{km}.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                    end
            end
        end

        % =================================================================

        function val = get.acceleration(h)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    val = System.Decimal.ToDouble(velpars.Acceleration);
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        velocityparams{km} = h.channel{km}.GetVelocityParams();             %#ok<AGROW> % update velocity parameter
                        val(km) = System.Decimal.ToDouble(velocityparams{km}.Acceleration); %#ok<AGROW> % update acceleration parameter
                    end
            end
        end

        % =================================================================

        function set.maxvelocity(h, val)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    % check physical limits
                    if val > h.vellimit
                        error('Requested acceleration is higher than the physical limit, which is %.2f',h.vellimit);
                    end
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    velpars.MaxVelocity = val;
                    h.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        % check physical limits
                        if val(km) > h.vellimit(km)
                            error('Requested velocity is higher than the physical limit for Ch%d, which is %.2f',km,h.vellimit(km));
                        end
                        velpars = h.channel{km}.GetVelocityParams(); % Get existing velocity and acceleration parameters
                        velpars.MaxVelocity = val(km);
                        h.channel{km}.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                    end
            end
        end

        % =================================================================

        function val = get.maxvelocity(h)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    val = System.Decimal.ToDouble(velpars.MaxVelocity);
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        velocityparams{km} = h.channel{km}.GetVelocityParams();             %#ok<AGROW> % update velocity parameter
                        val(km) = System.Decimal.ToDouble(velocityparams{km}.MaxVelocity); %#ok<AGROW> % update acceleration parameter
                    end
            end
        end

        % =================================================================

        function set.minvelocity(h, val)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    % check physical limits
                    if val > h.vellimit
                        error('Requested velocity is higher than the physical limit, which is %.2f',h.vellimit);
                    end
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    velpars.MinVelocity = val;
                    h.deviceNET.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        % check physical limits
                        if val(km) > h.vellimit(km)
                            error('Requested velocity is higher than the physical limit for Ch%d, which is %.2f',km,h.vellimit(km));
                        end
                        velpars = h.channel{km}.GetVelocityParams(); % Get existing velocity and acceleration parameters
                        velpars.MinVelocity = val(km);
                        h.channel{km}.SetVelocityParams(velpars); % Set velocity and acceleration paraneters via .NET interface
                    end
            end
        end

        % =================================================================

        function val = get.minvelocity(h)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    velpars = h.deviceNET.GetVelocityParams(); % Get existing velocity and acceleration parameters
                    val = System.Decimal.ToDouble(velpars.MinVelocity);
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        velocityparams{km} = h.channel{km}.GetVelocityParams();             %#ok<AGROW> % update velocity parameter
                        val(km) = System.Decimal.ToDouble(velocityparams{km}.MinVelocity); %#ok<AGROW> % update acceleration parameter
                    end
            end
        end

        % =================================================================

        function set.position(~, ~)
            error('You cannot set the Position property directly - please use moveto() function or similar!\n');
        end

        % =================================================================

        function val = get.position(h)
            switch(h.prefix)
                case {Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix,...
                        Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix}
                    val = System.Decimal.ToDouble(h.deviceNET.Position);        % Read current device position
                case Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103
                    for km = 1:double(h.deviceInfoNET.NumChannels)
                        val(km) = System.Decimal.ToDouble(h.channel{km}.Position); %#ok<AGROW> % Read current device position
                    end
            end
        end

        % =================================================================

        function relinc(h,deltaX)
            pos=System.Decimal.ToDouble(h.deviceNET.Position);
            if (pos + deltaX) > 12 || (pos + deltaX) < 0
                error("Cant exceed limits");
            end
            h.moveto(pos + deltaX);
        end %end of relative invrement

        % =================================================================

        function set.isconnected(h, val)
            if val == 1
                error('You cannot set the IsConnected property to 1 directly - please use connect(''serialnumber'') function!');
            elseif val == 0 && h.isconnected
                h.disconnect;
            else
                error('Unexpected value, could be only set to 0!');
            end
        end

        % =================================================================

        function val = get.isconnected(h)
            val = logical(h.deviceNET.IsConnected());
        end

    end

    %% M E T H O D S  (STATIC) - load DLLs, get a list of devices

    methods (Static)

        % =================================================================

        function serialNumbers = listdevices()  % Read a list of serial number of connected devices
            motor.loaddlls; % Load DLLs
            Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.Initialize;  % not really needed
            Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.BuildDeviceList();  % Build device list

            % create .NET list of suitable prefixes
            nPref = NET.createArray('System.Int32',3);
            nPref(1) = Thorlabs.MotionControl.KCube.DCServoCLI.KCubeDCServo.DevicePrefix;
            nPref(2) = Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix;
            nPref(3) = Thorlabs.MotionControl.Benchtop.BrushlessMotorCLI.BenchtopBrushlessMotor.DevicePrefix103;
            netPref = NET.createGeneric('System.Collections.Generic.List',{'System.Int32'},3);
            netPref.AddRange(nPref);

            serialNumbersNet = Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI.GetDeviceList(netPref);
            serialNumbers = cell(serialNumbersNet.ToArray); % Convert serial numbers to cell array

        end

        % =================================================================

        function loaddlls() % Load DLLs
            if ~exist(motor.INTEGSTEPCLASSNAME,'class')
                try   % Load in DLLs if not already loaded
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.DEVICEMANAGERDLL]);
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.GENERICMOTORDLL]);
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.DCSERVODLL]);
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.INTEGSTEPDLL]);
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.BRUSHLESSDLL]);
                    NET.addAssembly([motor.KINESISPATHDEFAULT,motor.PIEZODLL]);
                catch % DLLs did not load
                    error('Unable to load .NET assemblies')
                end
            end
        end

        % =================================================================

    end % methods (Static)

end % end of classdef

%% Outdated code but archive it

%                         h.triggers.pol_R_IO1 = string(tempConfig.Trigger1Polarity); % next assign the class properties to the contents of the temporary object
%                         h.triggers.pol_R_IO2 = string(tempConfig.Trigger2Polarity); % note that the conversion to char is for readability inside of the workspace
%                         h.triggers.mode_R_IO1 = string(tempConfig.Trigger1Mode);
%                         h.triggers.mode_R_IO2 = string(tempConfig.Trigger2Mode);
%                         h.triggers.pol_IO1 = tempConfig.Trigger1Polarity; % but we need ones that aren't readable for setting purposes
%                         h.triggers.pol_IO2 = tempConfig.Trigger2Polarity;
%                         h.triggers.mode_IO1 = tempConfig.Trigger1Mode;
%                         h.triggers.mode_IO2 = tempConfig.Trigger2Mode;
%                         clear tempConfig; % clear the temporary object