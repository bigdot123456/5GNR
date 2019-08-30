function y = constellation_rotation(x)
%rotates constellation w.r.t. angle given
%x is an array which consists of mapped signals
%modulation= 4,16,64,256 olabilir
%angle de�eri modulation type g�re de�i�ir
  
  global angle_bb  

  %angle=constellation_rotation_database(mod_type); % TODO: angle is global variable, has to be fixed
  y(1)= real(angle_bb*x(1))+imag(angle_bb*x(1))*1i;
  for i=2:length(x)
      y(i)= real(angle_bb*x(i))+imag(angle_bb*x(i))*1i;
  end;    
end

%sistem in entegresindeki niyetler
%--yap�ld�-- 1) angle de�eri databaseden gelicek
%2) real imag fonksiyonlar� cos ve sinus a��l�mlar� kullan�larak at�lacak

