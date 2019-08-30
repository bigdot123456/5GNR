%bits to cell word fonksiyonudur
%bitleri demultiplex ederek constelletions �ncesi interleave yapm�� olur
%bu fonksiyonun x'i bloklar� ay�rarark outputu olu�turur(Nsubsystems=blok_length.
%bu bloklar tam s�ral� de�ildir o y�zden database kullan�ld�
%28.01.2010  23.29

% global variables : nldpc_length,mod_type,Nsubstream 

function y = bits_to_cell_word_demultiplexer(x)
   global mod_type
   global nldpc_length
   global Nsubstream
   global demultiplexed

   nmod=log2(mod_type);
   %4_b_bit_to_cell_word_demultiplexer_parameter
   %demultiplexed=demultiplex_parameter(mod_type,fec_rate,nldpc_length); % Change according to database formation
   for i=1:nldpc_length/Nsubstream
       for k=1:Nsubstream
           y((i-1)*Nsubstream+k)=x((i-1)*Nsubstream + k -demultiplexed(Nsubstream-k+1));
       end;
   end;    
end

%gelecekte yap�lmas� niyetlenilen de�i�iklikler
%foksiyon bloklara y�rm��ken fonksiyonun bitmesi beklenmeden constellation
%i�eride yap�l�r b�ylece constellation i�eri yedirilmi� olur
%c yada dsp code da zaman kazan�labilece�ini d���n�yorum


% 4 Nisan  y((i-1)*Nsubstream+k)=x((i-1)*Nsubstream  -demultiplexed(Nsubstream-k+1));
%yerine y((i-1)*Nsubstream+k)=x((i-1)*Nsubstream + k -demultiplexed(Nsubstream-k+1));
% yaz�ld�.