x = [1.0 0.5 2.0 0.5 2.0];
y = [1.0 0.5 0.5 2.0 2.0];

figure;
plot(x,y,'x');

xlim([0 2.5]);
ylim([0 2.5]);

xlabel('energy consumption, EC');
ylabel('process rate, PR');

text(1.1,1.1,'1');
text(0.6,0.6,'2');
text(2.1,0.6,'3');
text(0.6,2.1,'4');
text(2.1,2.1,'5');
