function [to_frame_packet] = bicm_main(bbframe)

%Todo: Column_twisted_interleaver, reshape ile yap�lacak, S�leymanovi�
%yapacakm�� :)
global r_fec
global qldpc
global ldpc_par_adress 

un_time_interleaved = [];

len = length(bbframe);

for k = 1:r_fec;
    
    klpdc_frame = bch_create(bbframe( ( (k-1) * len/r_fec + 1 ) : ( k * len/r_fec ) ) );
    
    H= parity_matrix_gen(qldpc,ldpc_par_adress);
    
    l = fec.ldpcenc(H);
    
    nldpc_frame = encode(l, klpdc_frame);
   
    %nldpc_frame = ldpc_create(klpdc_frame); % Parity-bit-interleaver is applied in ldpc_create func.
 
    un_demux_Nldpc = column_twist_interleaved(nldpc_frame); % Nc, tc global variable;
 
    un_mapped_constellation = bits_to_cell_word_demultiplexer(un_demux_Nldpc);
 
    un_rotated_constellation = qamsquare_mod(un_mapped_constellation); 
    
    %un_cell_interleaved = constellation_rotation(un_rotated_constellation);
    %un_time_interleaved_part = cell_interleaver(un_cell_interleaved,k);
    
    un_time_interleaved_part = cell_interleaver(un_rotated_constellation,k);
    
    
    
    un_time_interleaved = [un_time_interleaved un_time_interleaved_part];
      
end

to_frame_packet =time_interleaver(un_time_interleaved); 



%%3-4 nisan notlari
%%qamsquare okey
%%bch_create de zero padding say�s� yanl��l��� d�zeltildi
%%ldpc_create de array parameter lerinde 0 indexleme hatas� d�zletildi
%%column twist interleaved de 0 indexleme hatas� d�zeltildi
%%column twist interleaved de for un ikinci indeksi yanl�� yaz�lm��
%%d�zeltildi
%%bits to cell demultiplexed 0 indexleme hatas� d�zeltildi
%%constellation rotation sorunsuz ge�ti









      
      





