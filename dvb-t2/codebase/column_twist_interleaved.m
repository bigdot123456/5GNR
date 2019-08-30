%--------------------------------------------------------------------------
%28.01.2010  16:37
%--------------------------------------------------------------------------
%column_twist_interleaved fonksiyonudur
%column ve row sat�rlar�n� kar��t�rarak(twist) interleave yapar
%ayr�ca column dada shift yapar tc nin de�erlerine g�re
%Nldpc=64800 veya 16200
%Nc modulation �e�idine g�re de�i�ir(16-qam,64-qam,256-qam)
%--------------------------------------------------------------------------
function column_twist_interleaved= column_twist_interleaved(y)
  global nldpc_length
  global Nc
  global tc
  global mod_type
  
  if mod_type == 4
      column_twist_interleaved = y;
  else
      column=nldpc_length/Nc;
      row=Nc;
      for i=1:column
        for k=1:row
           column_twist_interleaved((i-1)*row+k)= y(column*(k-1) + 1 + mod(i + column-tc(k),column));
        end;
      end;
  end;    
end
%--------------------------------------------------------------------------
%niyet edilen de�i�iklikler
%--yap�ld�---1)Nc ve tc de�erleri otomatik olarak hesaplanmas� global variable olabilir
%2)for d�g�s� yerine matrix memory yaz�p memoryden okuma olabilir
%  bu niyet c ve dsp code da daha verimli bir hesaplama verebilir
%--------------------------------------------------------------------------



% 3 nisan  mod(column - tc(k),column) yerine mod(i+column-tc(k),column)
% yaz�ld�