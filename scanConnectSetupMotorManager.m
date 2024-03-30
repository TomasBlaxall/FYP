function [xMotor, yMotor, zMotor] = scanConnectSetupMotorManager(xmotorsn, ymotorsn, zmotorsn, SNtext2text)
    
    motorSNs = {xmotorsn, ymotorsn, zmotorsn};
    motorObjects = cell(1, 3);
    
    for i = 1:3 % Create blank motorObjects and store them in the cell array
        motorObjects{i} = motor();  % Create a motor object
    end

    % for loop for iterating through the 3 previously made motorObjects
    for i = 1:3
        try
            activeSN = motorSNs{i};
            motorObjects{i}.connect(activeSN);
            motorObjects{i}.enable;
            if (motorObjects{i}.ishomed) == 0
                motorObjects{i}.home;
            end
            fprintf('Backlash for %s = %d',SNtext2text(activeSN),motorObjects{i}.GetBacklash);
        catch
            error('Error when using scanConnectSetupMotorManager function, errored out during setting loop')
        end
    end

    % Access the motorObjects by their names, first assign the names.
    xMotor = motorObjects{1};
    yMotor = motorObjects{2};
    zMotor = motorObjects{3};

end