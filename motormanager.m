classdef motormanager < handle
    % Class to manage the motor objects and handle things like moving axes in parallel and connecting to the motors also; need to add a constructor as well as destructor

    properties (Constant)
        xmotorSN = '27261675';
        ymotorSN = '27260767';
        zmotorSN = '27261911';
        text2SNtext = containers.Map({'X-Axis', 'Y-Axis', 'Z-Axis'}, {xmotorSN, ymotorSN, zmotorSN});
        SNtext2text = containers.Map({xmotorSN, ymotorSN, zmotorSN}, {'X-Axis', 'Y-Axis', 'Z-Axis'});
    end

    properties
        xMotor;
        yMotor;
        zMotor;
        writingVelocity;
        writingAcceleration;
    end



    methods (Sealed)
        function m = motormanager() % Constructor method
            try
                motor.loaddlls();
                SNs = motor.listdevices;
                if(numel(SNs) ~= 3) % if 3 devices can't be seen then print error information
                    fprintf('Devices that can be seen:');
                    for i=1:numel(SNs)
                        disp(SNtext2text(SNs(i)));
                    end
                    error(['Something went wrong or something not connected, cannot see all 3 devices %s', ":("]);
                end
            catch
                error(['critical error in instantiating motor manager %s', SNs]);
            end % if all 3 devices can be seen 
            try % try to create motor objects using the scanConnectSetupMotorManager function
                [m.xMotor, m.yMotor, m.zMotor] = scanConnectSetupMotorManager(xmotorsn, ymotorsn, zmotorsn, SNtext2text);
            catch
                error('error when trying to use the scanConnectSetupMotorManager function when instantiating the motor manager class, error from class not from function');
            end
        end



        function XY_Move(m, xEnd, yEnd, triggerParams) % takes the desired x and y positions and the magnitude of the absolute velocity desired for the move to perform the move
            
            % Calculate componentwise velocities required
            xStart = m.xMotor.position();
            yStart = m.yMotor.position;
            xStartVelocity = m.xMotor.maxvelocity; % xmotor limit to return value back to xmotor later
            yStartVelocity = m.yMotor.maxvelocity; % ymotor limit to return value back later
            xMoveDist = abs(xEnd-xStart);
            yMoveDist = abs(yEnd-yStart);
            totalDist = sqrt((xMoveMagnitude^(2))+(yMoveMagnitude^(2)));
            time = totalDist/m.writingVelocity;
            velY = sqrt((-1*(((xMoveDist*time)^(2))-(m.writingVelocity^(2)))));
            velX = sqrt((-1*(((yMoveDist*time)^(2))-(m.writingVelocity^(2)))));
            % Now we have the component XY velocities we can set the individual motors to these velocities
            m.xMotor.maxvelocity = velX;
            m.yMotor.maxvelocity = velY;
            % The motors have had their velocities set, next we set the trigger parameters for time reasons maybe instead of setting here it would be better to set it between moves and simply
            % check a property inside of the motor manager class but I haven't decided what will be best just yet. This is just a placeholder for now that would still work
            m.xMotor.setDeviceTriggerParams(triggerParams);
            m.yMotor.setDeviceTriggerParams(triggerParams);
            pause(0.05);
            % make movement using movepar command
            m.xMotor.movetopar(xEnd);
            m.yMotor.moveto(yEnd); % may need to be replaced with movetopar in case the waithandler causes any issues.
            % the motor drivers can be set to register an output once the motor has stopped, this can be used as the signal to do something again coming back from the movetopar command.
            % this will be achieved with a while loop and the ESP32

            % We have the signal that the move is complete and now we reset
                        

        end
    end



end