#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build Resources/Localizable.xcstrings from tools/strings_en.json + the
translation table below.

Re-runnable: it always rewrites the catalogue from scratch.
To add a language: append its code to LANGUAGES and add one entry per key
in TRANSLATIONS (and in PLURALS for the plural-governed keys).

    python3 tools/build_xcstrings.py
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(HERE, "strings_en.json")
OUTPUT = os.path.join(ROOT, "Resources", "Localizable.xcstrings")

SOURCE_LANGUAGE = "en"
# order of the tuples in TRANSLATIONS
LANGUAGES = ["fr", "es", "de", "it", "pt"]

# ---------------------------------------------------------------------------
# GLOSSARY (kept identical across the whole app)
#
#            EN            FR              ES              DE              IT              PT
# trip       trip          trajet          viaje           Fahrt           viaggio         viagem
# business   business      professionnel   profesional     geschäftlich    di lavoro       de trabalho
# personal   personal      personnel       personal        privat          personale       pessoal
# mileage    mileage       kilométrique    kilometraje     Kilometer-      chilometrico    quilometragem
# rate       rate          taux            tarifa          Satz            tariffa         taxa
# scale/rule scale, rule   barème          baremo          Pauschale       tabella         tabela
# report     report        rapport         informe         Bericht         report          relatório
# vehicle    vehicle       véhicule        vehículo        Fahrzeug        veicolo         veículo
# distance   distance      distance        distancia       Strecke         distanza        distância
# purpose    purpose       motif           motivo          Zweck           motivo          motivo
# client     client        client          cliente         Kunde           cliente         cliente
#
# Register: tu/du/tu/tu informal in ES/DE/IT/PT, vous in FR (Apple FR standard).
# PT is European Portuguese (registo, Definições, quilómetros, carrinha, mota).
# ---------------------------------------------------------------------------

# key -> (fr, es, de, it, pt)
TRANSLATIONS = {
    # --- app / tabs -------------------------------------------------------
    "app.name": ("Mileage Pocket", "Mileage Pocket", "Mileage Pocket",
                 "Mileage Pocket", "Mileage Pocket"),
    "tab.home": ("Accueil", "Inicio", "Start", "Home", "Início"),
    "tab.trips": ("Trajets", "Viajes", "Fahrten", "Viaggi", "Viagens"),
    "tab.reports": ("Rapports", "Informes", "Berichte", "Report", "Relatórios"),
    "tab.settings": ("Réglages", "Ajustes", "Einstellungen", "Impostazioni", "Definições"),

    # --- common -----------------------------------------------------------
    "common.save": ("Enregistrer", "Guardar", "Speichern", "Salva", "Guardar"),
    "common.cancel": ("Annuler", "Cancelar", "Abbrechen", "Annulla", "Cancelar"),
    "common.discard": ("Abandonner", "Descartar", "Verwerfen", "Ignora", "Descartar"),
    "common.delete": ("Supprimer", "Eliminar", "Löschen", "Elimina", "Apagar"),
    "common.done": ("Terminé", "Listo", "Fertig", "Fine", "Concluído"),
    "common.continue": ("Continuer", "Continuar", "Weiter", "Continua", "Continuar"),
    "common.ok": ("OK", "OK", "OK", "OK", "OK"),
    "common.close": ("Fermer", "Cerrar", "Schließen", "Chiudi", "Fechar"),

    # --- home -------------------------------------------------------------
    "home.start": ("START", "INICIAR", "START", "AVVIA", "INICIAR"),
    "home.start.accessibility": ("Démarrer le trajet", "Iniciar viaje", "Fahrt starten",
                                 "Avvia viaggio", "Iniciar viagem"),
    "home.estimated": ("Environ %@", "Aprox. %@", "ca. %@", "Circa %@", "Aprox. %@"),
    "home.last.trip": ("Dernier trajet", "Último viaje", "Letzte Fahrt",
                       "Ultimo viaggio", "Última viagem"),
    "home.no.vehicle": ("Aucun véhicule", "Sin vehículo", "Kein Fahrzeug",
                        "Nessun veicolo", "Sem veículo"),
    "home.vehicle": ("Véhicule", "Vehículo", "Fahrzeug", "Veicolo", "Veículo"),
    "home.empty.title": ("Aucun trajet", "Aún no hay viajes", "Noch keine Fahrten",
                         "Ancora nessun viaggio", "Ainda sem viagens"),
    "home.empty.message": (
        "Appuyez sur START quand vous partez. Votre premier relevé kilométrique ne prend qu’un geste.",
        "Pulsa INICIAR cuando salgas. Tu primer registro de kilometraje está a un toque.",
        "Tipp auf START, wenn du losfährst. Deine erste Fahrt ist nur einen Fingertipp entfernt.",
        "Tocca AVVIA quando parti. Il tuo primo viaggio è a un tocco di distanza.",
        "Toca em INICIAR quando saíres. O teu primeiro registo de quilometragem fica a um toque.",
    ),

    # --- active trip ------------------------------------------------------
    "activetrip.recording": ("Trajet en cours", "Viaje en curso", "Fahrt läuft",
                             "Viaggio in corso", "Viagem em curso"),
    "activetrip.paused": ("À l’arrêt", "Detenido", "Angehalten", "Fermo", "Parado"),
    "activetrip.stop": ("STOP", "STOP", "STOP", "STOP", "STOP"),
    "activetrip.stop.accessibility": ("Arrêter le trajet", "Detener viaje", "Fahrt beenden",
                                      "Termina viaggio", "Terminar viagem"),
    "activity.title": ("Trajet en cours", "Viaje en curso", "Fahrt läuft",
                       "Viaggio in corso", "Viagem em curso"),

    # --- trip type --------------------------------------------------------
    "trip.type.business": ("Professionnel", "Profesional", "Geschäftlich", "Lavoro", "Trabalho"),
    "trip.type.personal": ("Personnel", "Personal", "Privat", "Personale", "Pessoal"),

    # --- summary ----------------------------------------------------------
    "summary.title": ("Trajet enregistré", "Viaje guardado", "Fahrt gespeichert",
                      "Viaggio salvato", "Viagem guardada"),
    "summary.purpose": ("Motif", "Motivo", "Zweck", "Motivo", "Motivo"),
    "summary.purpose.placeholder": ("Pourquoi ce trajet ?", "¿Para qué fue este viaje?",
                                    "Wofür war diese Fahrt?", "A cosa serviva questo viaggio?",
                                    "Para que foi esta viagem?"),
    "summary.client": ("Client", "Cliente", "Kunde", "Cliente", "Cliente"),
    "summary.client.placeholder": ("Client ou projet", "Cliente o proyecto",
                                   "Kunde oder Projekt", "Cliente o progetto",
                                   "Cliente ou projeto"),
    "summary.suggestion": ("Ici, vous allez d’habitude chez %@", "Aquí sueles ir a %@",
                           "Hier fährst du sonst zu %@", "Qui di solito vai da %@",
                           "Aqui costumas ir a %@"),
    "summary.suggestion.apply": ("Utiliser", "Usar", "Übernehmen", "Usa", "Usar"),

    # --- purpose ----------------------------------------------------------
    "purpose.clientVisit": ("Visite client", "Visita a cliente", "Kundenbesuch",
                            "Visita cliente", "Visita a cliente"),
    "purpose.meeting": ("Réunion", "Reunión", "Besprechung", "Riunione", "Reunião"),
    "purpose.delivery": ("Livraison", "Entrega", "Lieferung", "Consegna", "Entrega"),
    "purpose.siteVisit": ("Visite de site", "Visita a obra", "Vor-Ort-Termin",
                          "Sopralluogo", "Visita a obra"),
    "purpose.other": ("Autre", "Otro", "Sonstiges", "Altro", "Outro"),

    # --- trips list -------------------------------------------------------
    "trips.section.today": ("Aujourd’hui", "Hoy", "Heute", "Oggi", "Hoje"),
    "trips.section.yesterday": ("Hier", "Ayer", "Gestern", "Ieri", "Ontem"),
    "trips.section.thisweek": ("Cette semaine", "Esta semana", "Diese Woche",
                               "Questa settimana", "Esta semana"),
    "trips.section.earlier": ("Avant", "Antes", "Früher", "Prima", "Antes"),
    "trips.empty.title": ("Aucun trajet à afficher", "No hay viajes que mostrar",
                          "Keine Fahrten vorhanden", "Nessun viaggio da mostrare",
                          "Sem viagens para mostrar"),
    "trips.empty.message": (
        "Les trajets enregistrés s’affichent ici, du plus récent au plus ancien. Vous pouvez aussi en ajouter un à la main.",
        "Los viajes que registres aparecen aquí, del más reciente al más antiguo. También puedes añadir uno a mano.",
        "Aufgezeichnete Fahrten erscheinen hier, die neueste zuerst. Du kannst auch eine von Hand hinzufügen.",
        "I viaggi registrati compaiono qui, dal più recente al più vecchio. Puoi anche aggiungerne uno a mano.",
        "As viagens que registares aparecem aqui, da mais recente para a mais antiga. Também podes adicionar uma à mão.",
    ),
    "trips.search": ("Rechercher un trajet", "Buscar viajes", "Fahrten suchen",
                     "Cerca viaggi", "Procurar viagens"),
    "trips.filter": ("Filtrer", "Filtrar", "Filter", "Filtra", "Filtrar"),
    "trips.filter.all": ("Tous les trajets", "Todos los viajes", "Alle Fahrten",
                         "Tutti i viaggi", "Todas as viagens"),
    "trips.add.manual": ("Ajouter un trajet à la main", "Añadir viaje a mano",
                         "Fahrt von Hand hinzufügen", "Aggiungi viaggio a mano",
                         "Adicionar viagem à mão"),

    # --- trip detail ------------------------------------------------------
    "detail.from": ("De", "Desde", "Von", "Da", "De"),
    "detail.to": ("À", "Hasta", "Nach", "A", "Para"),
    "detail.departure": ("Départ", "Salida", "Abfahrt", "Partenza", "Partida"),
    "detail.arrival": ("Arrivée", "Llegada", "Ankunft", "Arrivo", "Chegada"),
    "detail.duration": ("Durée", "Duración", "Dauer", "Durata", "Duração"),
    "detail.vehicle": ("Véhicule", "Vehículo", "Fahrzeug", "Veicolo", "Veículo"),
    "detail.purpose": ("Motif", "Motivo", "Zweck", "Motivo", "Motivo"),
    "detail.client": ("Client", "Cliente", "Kunde", "Cliente", "Cliente"),
    "detail.country": ("Pays", "País", "Land", "Paese", "País"),
    "detail.rate": ("Taux", "Tarifa", "Kilometersatz", "Tariffa", "Taxa"),
    "detail.rule": ("Barème", "Baremo", "Pauschale", "Tabella", "Tabela"),
    "detail.rule.version": ("Version du barème", "Versión del baremo", "Version der Pauschale",
                            "Versione della tabella", "Versão da tabela"),
    "detail.edited": ("Distance modifiée", "Distancia editada", "Strecke bearbeitet",
                      "Distanza modificata", "Distância editada"),
    "detail.edit.distance": ("Modifier la distance", "Editar distancia", "Strecke bearbeiten",
                             "Modifica distanza", "Editar distância"),
    "detail.edit.distance.message": (
        "La distance enregistrée est conservée. Le montant est recalculé avec le taux déjà appliqué à ce trajet.",
        "Se conserva la distancia registrada. El importe se recalcula con la tarifa ya aplicada a este viaje.",
        "Die aufgezeichnete Strecke bleibt erhalten. Der Betrag wird mit dem Kilometersatz neu berechnet, der für diese Fahrt bereits gilt.",
        "La distanza registrata resta invariata. L’importo viene ricalcolato con la tariffa già applicata a questo viaggio.",
        "A distância registada mantém-se. O valor é recalculado com a taxa já aplicada a esta viagem.",
    ),
    "detail.recalculate": ("Recalculer avec les barèmes actuels", "Recalcular con los baremos actuales",
                           "Mit aktueller Pauschale neu berechnen", "Ricalcola con le tabelle attuali",
                           "Recalcular com as tabelas atuais"),
    "detail.recalculate.confirm": ("Recalculer", "Recalcular", "Neu berechnen",
                                   "Ricalcola", "Recalcular"),
    "detail.recalculate.message": (
        "Le taux enregistré avec ce trajet est remplacé par celui en vigueur aujourd’hui. En principe, un trajet ancien garde le taux applicable au moment où il a été effectué.",
        "La tarifa guardada con este viaje se sustituye por la vigente hoy. Normalmente, un viaje antiguo conserva la tarifa que se aplicaba cuando lo hiciste.",
        "Der mit dieser Fahrt gespeicherte Kilometersatz wird durch den heute gültigen ersetzt. Ältere Fahrten behalten normalerweise den Satz, der am Tag der Fahrt galt.",
        "La tariffa salvata con questo viaggio viene sostituita da quella in vigore oggi. Di norma, un viaggio passato mantiene la tariffa valida nel giorno in cui è stato fatto.",
        "A taxa guardada com esta viagem é substituída pela que está em vigor hoje. Normalmente, uma viagem antiga mantém a taxa aplicável na data em que foi feita.",
    ),
    "detail.duplicate": ("Dupliquer", "Duplicar", "Duplizieren", "Duplica", "Duplicar"),
    "detail.start": ("Début", "Inicio", "Start", "Inizio", "Início"),
    "detail.end": ("Fin", "Fin", "Ende", "Fine", "Fim"),

    # --- manual entry -----------------------------------------------------
    "manual.title": ("Ajouter un trajet", "Añadir un viaje", "Fahrt hinzufügen",
                     "Aggiungi un viaggio", "Adicionar uma viagem"),
    "manual.date": ("Date", "Fecha", "Datum", "Data", "Data"),
    "manual.from": ("De", "Desde", "Von", "Da", "De"),
    "manual.to": ("À", "Hasta", "Nach", "A", "Para"),
    "manual.distance": ("Distance", "Distancia", "Strecke", "Distanza", "Distância"),
    "manual.type": ("Type", "Tipo", "Art", "Tipo", "Tipo"),
    "manual.vehicle": ("Véhicule", "Vehículo", "Fahrzeug", "Veicolo", "Veículo"),
    "manual.vehicle.none": ("Aucun", "Ninguno", "Keines", "Nessuno", "Nenhum"),

    # --- reports ----------------------------------------------------------
    "reports.period": ("Période", "Periodo", "Zeitraum", "Periodo", "Período"),
    "reports.period.month": ("Mois", "Mes", "Monat", "Mese", "Mês"),
    "reports.period.quarter": ("Trimestre", "Trimestre", "Quartal", "Trimestre", "Trimestre"),
    "reports.period.year": ("Année", "Año", "Jahr", "Anno", "Ano"),
    "reports.period.custom": ("Libre", "Libre", "Frei", "Libero", "Livre"),
    "reports.from": ("Du", "Desde", "Von", "Dal", "De"),
    "reports.to": ("Au", "Hasta", "Bis", "Al", "Até"),
    "reports.trips": ("Trajets professionnels", "Viajes profesionales", "Geschäftliche Fahrten",
                      "Viaggi di lavoro", "Viagens de trabalho"),
    "reports.distance": ("Distance", "Distancia", "Strecke", "Distanza", "Distância"),
    "reports.total": ("Total", "Total", "Gesamt", "Totale", "Total"),
    "reports.generate": ("GÉNÉRER LE RAPPORT", "GENERAR INFORME", "BERICHT ERSTELLEN",
                         "GENERA REPORT", "GERAR RELATÓRIO"),
    "reports.csv": ("Exporter en CSV", "Exportar en CSV", "Als CSV exportieren",
                    "Esporta in CSV", "Exportar para CSV"),
    "reports.empty.hint": (
        "Aucun trajet professionnel sur cette période. Le rapport sera vide.",
        "No hay viajes profesionales en este periodo. El informe saldrá vacío.",
        "In diesem Zeitraum gibt es noch keine geschäftlichen Fahrten. Der Bericht bleibt leer.",
        "Nessun viaggio di lavoro in questo periodo. Il report sarà vuoto.",
        "Ainda não há viagens de trabalho neste período. O relatório ficará vazio.",
    ),

    # --- vehicles ---------------------------------------------------------
    "vehicles.title": ("Véhicules", "Vehículos", "Fahrzeuge", "Veicoli", "Veículos"),
    "vehicles.add": ("Ajouter un véhicule", "Añadir vehículo", "Fahrzeug hinzufügen",
                     "Aggiungi veicolo", "Adicionar veículo"),
    "vehicles.default": ("Par défaut", "Predeterminado", "Standard", "Predefinito", "Predefinido"),
    "vehicles.empty.title": ("Aucun véhicule", "Aún no hay vehículos", "Noch kein Fahrzeug",
                             "Ancora nessun veicolo", "Ainda sem veículos"),
    "vehicles.empty.message": (
        "Ajoutez la voiture que vous utilisez pour le travail. Les trajets fonctionnent sans, mais les rapports sont plus clairs avec.",
        "Añade el coche que usas para trabajar. Puedes registrar viajes sin él, pero los informes quedan más claros con él.",
        "Füge das Auto hinzu, mit dem du für die Arbeit fährst. Fahrten lassen sich auch ohne aufzeichnen, aber die Berichte werden damit klarer.",
        "Aggiungi l’auto che usi per lavoro. Puoi registrare i viaggi anche senza, ma i report sono più chiari indicandola.",
        "Adiciona o carro que usas para trabalhar. Podes registar viagens sem ele, mas os relatórios ficam mais claros com ele.",
    ),
    "vehicle.name": ("Nom", "Nombre", "Name", "Nome", "Nome"),
    "vehicle.type": ("Type", "Tipo", "Art", "Tipo", "Tipo"),
    "vehicle.registration": ("Immatriculation", "Matrícula", "Kennzeichen", "Targa", "Matrícula"),
    "vehicle.set.default": ("Utiliser comme véhicule par défaut", "Usar como vehículo predeterminado",
                            "Als Standardfahrzeug verwenden", "Usa come veicolo predefinito",
                            "Usar como veículo predefinido"),
    "vehicle.fiscal.horsepower": ("Chevaux fiscaux", "Potencia fiscal", "Steuer-PS",
                                  "Cavalli fiscali", "Cavalos fiscais"),
    "vehicle.fiscal.horsepower.help": (
        "Le barème kilométrique de votre pays utilise les chevaux fiscaux. Ils figurent sur votre carte grise.",
        "El baremo de kilometraje de tu país usa la potencia fiscal. Aparece en el permiso de circulación.",
        "Die Kilometerpauschale deines Landes richtet sich nach den Steuer-PS. Sie stehen in deinem Fahrzeugschein.",
        "La tabella chilometrica del tuo paese usa i cavalli fiscali. Sono indicati sul libretto di circolazione.",
        "A tabela de quilometragem do teu país usa os cavalos fiscais. Estão indicados no documento único automóvel.",
    ),
    "vehicle.engine.capacity": ("Cylindrée (cm³)", "Cilindrada (cc)", "Hubraum (cm³)",
                                "Cilindrata (cc)", "Cilindrada (cc)"),
    "vehicle.engine.capacity.help": (
        "Le barème kilométrique de votre pays utilise la cylindrée. Elle figure sur votre carte grise.",
        "El baremo de kilometraje de tu país usa la cilindrada. Aparece en el permiso de circulación.",
        "Die Kilometerpauschale deines Landes richtet sich nach dem Hubraum. Er steht in deinem Fahrzeugschein.",
        "La tabella chilometrica del tuo paese usa la cilindrata. È indicata sul libretto di circolazione.",
        "A tabela de quilometragem do teu país usa a cilindrada. Está indicada no documento único automóvel.",
    ),
    "vehicle.type.car": ("Voiture", "Coche", "Auto", "Auto", "Carro"),
    "vehicle.type.electricCar": ("Voiture électrique", "Coche eléctrico", "Elektroauto",
                                 "Auto elettrica", "Carro elétrico"),
    "vehicle.type.van": ("Utilitaire", "Furgoneta", "Transporter", "Furgone", "Carrinha"),
    "vehicle.type.motorcycle": ("Moto", "Moto", "Motorrad", "Moto", "Mota"),
    "vehicle.type.moped": ("Cyclomoteur", "Ciclomotor", "Moped", "Ciclomotore", "Ciclomotor"),
    "vehicle.type.bicycle": ("Vélo", "Bicicleta", "Fahrrad", "Bicicletta", "Bicicleta"),

    # --- settings ---------------------------------------------------------
    "settings.account": ("Compte", "Cuenta", "Account", "Account", "Conta"),
    "settings.name": ("Nom", "Nombre", "Name", "Nome", "Nome"),
    "settings.company": ("Société", "Empresa", "Unternehmen", "Azienda", "Empresa"),
    "settings.email": ("E-mail", "Correo", "E-Mail", "E-mail", "E-mail"),
    "settings.driving": ("Conduite", "Conducción", "Fahren", "Guida", "Condução"),
    "settings.vehicles": ("Véhicules", "Vehículos", "Fahrzeuge", "Veicoli", "Veículos"),
    "settings.default.type": ("Type de trajet par défaut", "Tipo de viaje predeterminado",
                              "Standard-Fahrtart", "Tipo di viaggio predefinito",
                              "Tipo de viagem predefinido"),
    "settings.units": ("Unités", "Unidades", "Einheiten", "Unità", "Unidades"),
    "settings.units.km": ("Kilomètres", "Kilómetros", "Kilometer", "Chilometri", "Quilómetros"),
    "settings.units.mi": ("Miles", "Millas", "Meilen", "Miglia", "Milhas"),
    "settings.region": ("Région", "Región", "Region", "Regione", "Região"),
    "settings.country": ("Pays", "País", "Land", "Paese", "País"),
    "settings.country.search": ("Rechercher un pays", "Buscar países", "Länder suchen",
                                "Cerca paesi", "Procurar países"),
    "settings.language": ("Langue", "Idioma", "Sprache", "Lingua", "Idioma"),
    "settings.currency": ("Devise", "Moneda", "Währung", "Valuta", "Moeda"),
    "settings.calculation": ("Calcul kilométrique", "Cálculo del kilometraje",
                             "Kilometerberechnung", "Calcolo chilometrico",
                             "Cálculo da quilometragem"),
    "settings.rate.mode": ("Taux", "Tarifa", "Kilometersatz", "Tariffa", "Taxa"),
    "settings.rate.employer": ("Taux employeur", "Tarifa de la empresa", "Arbeitgebersatz",
                               "Tariffa aziendale", "Taxa da empresa"),
    "settings.rate.custom": ("Taux personnalisé", "Tarifa personalizada", "Eigener Satz",
                             "Tariffa personalizzata", "Taxa personalizada"),
    "settings.active.rule": ("Barème actif", "Baremo activo", "Aktive Pauschale",
                             "Tabella attiva", "Tabela ativa"),
    "settings.rule.source": ("Voir la source officielle", "Ver la fuente oficial",
                             "Offizielle Quelle ansehen", "Vedi la fonte ufficiale",
                             "Ver a fonte oficial"),
    "settings.no.official.rule": (
        "Mileage Pocket n’a pas de barème officiel vérifié pour ce pays : c’est votre propre taux qui s’applique. Le suivi, l’historique et les rapports fonctionnent exactement pareil.",
        "Mileage Pocket no tiene un baremo oficial verificado para este país, así que se usa tu propia tarifa. El seguimiento, el historial y los informes funcionan igual.",
        "Für dieses Land hat Mileage Pocket keine geprüfte offizielle Pauschale, deshalb gilt dein eigener Satz. Aufzeichnung, Verlauf und Berichte funktionieren genauso.",
        "Mileage Pocket non ha una tabella ufficiale verificata per questo paese, quindi si usa la tua tariffa. Registrazione, cronologia e report funzionano allo stesso modo.",
        "O Mileage Pocket não tem uma tabela oficial verificada para este país, por isso é usada a tua taxa. O registo, o histórico e os relatórios funcionam da mesma forma.",
    ),
    "settings.data": ("Données", "Datos", "Daten", "Dati", "Dados"),
    "settings.icloud": ("Synchronisation iCloud", "Sincronización con iCloud", "iCloud-Sync",
                        "Sincronizzazione iCloud", "Sincronização com o iCloud"),
    "settings.export.all": ("Exporter toutes mes données", "Exportar todos mis datos",
                            "Alle meine Daten exportieren", "Esporta tutti i miei dati",
                            "Exportar todos os meus dados"),
    "settings.delete.all": ("Supprimer toutes les données", "Eliminar todos los datos",
                            "Alle Daten löschen", "Elimina tutti i dati",
                            "Apagar todos os dados"),
    "settings.delete.all.confirm": ("Tout supprimer", "Eliminar todo", "Alles löschen",
                                    "Elimina tutto", "Apagar tudo"),
    "settings.delete.all.message": (
        "Tous les trajets, véhicules et clients sont supprimés de cet iPhone et d’iCloud. C’est irréversible.",
        "Se eliminan todos los viajes, vehículos y clientes de este iPhone y de iCloud. No se puede deshacer.",
        "Alle Fahrten, Fahrzeuge und Kunden werden von diesem iPhone und aus iCloud gelöscht. Das lässt sich nicht rückgängig machen.",
        "Tutti i viaggi, i veicoli e i clienti vengono eliminati da questo iPhone e da iCloud. L’operazione è irreversibile.",
        "Todas as viagens, veículos e clientes são apagados deste iPhone e do iCloud. Não é possível anular.",
    ),
    "settings.subscription": ("Abonnement", "Suscripción", "Abo", "Abbonamento", "Subscrição"),
    "settings.plan": ("Formule actuelle", "Plan actual", "Aktuelles Abo", "Piano attuale",
                      "Plano atual"),
    "settings.manage": ("Gérer l’abonnement", "Gestionar suscripción", "Abo verwalten",
                        "Gestisci abbonamento", "Gerir subscrição"),
    "settings.subscribe": ("Voir les formules", "Ver planes", "Abos ansehen", "Vedi i piani",
                           "Ver planos"),
    "settings.plan.free": ("Sans abonnement", "Sin suscripción", "Kein Abo",
                           "Nessun abbonamento", "Sem subscrição"),
    "settings.plan.trial": ("Essai gratuit", "Prueba gratuita", "Gratis-Testphase",
                            "Prova gratuita", "Teste gratuito"),
    "settings.plan.grace": ("Problème de paiement", "Problema de pago", "Zahlungsproblem",
                            "Problema di pagamento", "Problema de pagamento"),
    "settings.about": ("À propos", "Información", "Info", "Informazioni", "Acerca de"),
    "settings.support": ("Contacter l’assistance", "Contactar con soporte", "Support kontaktieren",
                         "Contatta l’assistenza", "Contactar o suporte"),
    "settings.version": ("Version", "Versión", "Version", "Versione", "Versão"),

    # --- rate modes -------------------------------------------------------
    "rate.official": ("Taux officiel", "Tarifa oficial", "Offizieller Satz",
                      "Tariffa ufficiale", "Taxa oficial"),
    "rate.employer": ("Taux employeur", "Tarifa de la empresa", "Arbeitgebersatz",
                      "Tariffa aziendale", "Taxa da empresa"),
    "rate.custom": ("Taux personnalisé", "Tarifa personalizada", "Eigener Satz",
                    "Tariffa personalizzata", "Taxa personalizada"),

    # --- paywall ----------------------------------------------------------
    "paywall.headline": ("Vos kilomètres. Justifiés automatiquement.",
                         "Tus kilómetros. Justificados automáticamente.",
                         "Deine Kilometer. Automatisch belegt.",
                         "I tuoi chilometri. Documentati in automatico.",
                         "Os teus quilómetros. Justificados automaticamente."),
    "paywall.feature.tracking": ("Suivi illimité des trajets", "Registro de viajes ilimitado",
                                 "Unbegrenzt Fahrten aufzeichnen", "Registrazione viaggi illimitata",
                                 "Registo de viagens ilimitado"),
    "paywall.feature.calculations": ("Calculs kilométriques", "Cálculo del kilometraje",
                                     "Kilometerberechnung", "Calcolo chilometrico",
                                     "Cálculo da quilometragem"),
    "paywall.feature.pdf": ("Rapports PDF mensuels", "Informes PDF mensuales",
                            "Monatliche PDF-Berichte", "Report PDF mensili",
                            "Relatórios PDF mensais"),
    "paywall.feature.csv": ("Exports CSV", "Exportaciones CSV", "CSV-Exporte",
                            "Esportazioni CSV", "Exportações CSV"),
    "paywall.feature.vehicles": ("Plusieurs véhicules", "Varios vehículos", "Mehrere Fahrzeuge",
                                 "Più veicoli", "Vários veículos"),
    "paywall.feature.icloud": ("Sauvegarde iCloud", "Copia de seguridad en iCloud", "iCloud-Backup",
                               "Backup su iCloud", "Cópia de segurança no iCloud"),
    "paywall.plan.monthly": ("Mensuel", "Mensual", "Monatlich", "Mensile", "Mensal"),
    "paywall.plan.annual": ("Annuel", "Anual", "Jährlich", "Annuale", "Anual"),
    "paywall.per.month": ("par mois", "al mes", "pro Monat", "al mese", "por mês"),
    "paywall.per.year": ("par an", "al año", "pro Jahr", "all’anno", "por ano"),
    "paywall.save": ("Économisez %lld%%", "Ahorra un %lld%%", "%lld%% sparen",
                     "Risparmia il %lld%%", "Poupa %lld%%"),
    "paywall.cta.trial": ("Commencer l’essai gratuit de 3 jours", "Empezar la prueba gratuita de 3 días",
                          "3 Tage gratis testen", "Inizia la prova gratuita di 3 giorni",
                          "Começar o teste gratuito de 3 dias"),
    "paywall.cta.subscribe": ("S’abonner", "Suscribirse", "Abonnieren", "Abbonati", "Subscrever"),
    "paywall.footer.trial": ("3 jours gratuits, puis %@. Annulable à tout moment.",
                             "3 días gratis y luego %@. Cancela cuando quieras.",
                             "3 Tage gratis, danach %@. Jederzeit kündbar.",
                             "3 giorni gratis, poi %@. Disdici quando vuoi.",
                             "3 dias grátis, depois %@. Cancela quando quiseres."),
    "paywall.footer.plain": ("%@. Annulable à tout moment.", "%@. Cancela cuando quieras.",
                             "%@. Jederzeit kündbar.", "%@. Disdici quando vuoi.",
                             "%@. Cancela quando quiseres."),
    "paywall.restore": ("Restaurer", "Restaurar", "Wiederherstellen", "Ripristina", "Restaurar"),
    "paywall.terms": ("Conditions", "Condiciones", "AGB", "Termini", "Termos"),
    "paywall.privacy": ("Confidentialité", "Privacidad", "Datenschutz", "Privacy", "Privacidade"),
    "paywall.error": ("Une erreur est survenue", "Algo ha fallado", "Etwas ist schiefgelaufen",
                      "Qualcosa è andato storto", "Algo correu mal"),

    # --- onboarding -------------------------------------------------------
    "onboarding.welcome.headline": ("Chaque kilomètre professionnel compté.",
                                    "Cada kilómetro profesional, contado.",
                                    "Jeden geschäftlichen Kilometer erfassen.",
                                    "Ogni chilometro di lavoro, registrato.",
                                    "Cada quilómetro de trabalho, registado."),
    "onboarding.welcome.subtitle": (
        "Démarrez le trajet. Roulez. Arrêtez-vous. Votre rapport kilométrique est prêt.",
        "Inicia el viaje. Conduce. Detente. Tu informe de kilometraje está listo.",
        "Fahrt starten. Fahren. Beenden. Dein Kilometerbericht ist fertig.",
        "Avvia il viaggio. Guida. Fermati. Il tuo report chilometrico è pronto.",
        "Inicia a viagem. Conduz. Termina. O teu relatório de quilometragem está pronto.",
    ),
    "onboarding.country.title": ("Votre pays", "Tu país", "Dein Land", "Il tuo paese", "O teu país"),
    "onboarding.country.subtitle": (
        "Cela détermine votre devise, vos unités et le barème kilométrique appliqué à vos trajets.",
        "Define tu moneda, tus unidades y el baremo de kilometraje que se aplica a tus viajes.",
        "Das legt deine Währung, deine Einheiten und die Kilometerpauschale für deine Fahrten fest.",
        "Determina la valuta, le unità e la tabella chilometrica applicata ai tuoi viaggi.",
        "Define a tua moeda, as tuas unidades e a tabela de quilometragem aplicada às tuas viagens.",
    ),
    "onboarding.country.official": ("Barème officiel disponible : %@", "Baremo oficial disponible: %@",
                                    "Offizielle Pauschale verfügbar: %@", "Tabella ufficiale disponibile: %@",
                                    "Tabela oficial disponível: %@"),
    "onboarding.country.custom": (
        "Aucun barème officiel n’est intégré pour ce pays. Vous définirez votre propre taux, tout le reste fonctionne pareil.",
        "No hay un baremo oficial integrado para este país. Definirás tu propia tarifa y todo lo demás funciona igual.",
        "Für dieses Land ist keine offizielle Pauschale hinterlegt. Du legst deinen eigenen Satz fest, alles andere bleibt gleich.",
        "Per questo paese non è inclusa una tabella ufficiale. Imposterai la tua tariffa e tutto il resto funziona uguale.",
        "Não existe uma tabela oficial integrada para este país. Vais definir a tua própria taxa e tudo o resto funciona igual.",
    ),
    "onboarding.vehicle.title": ("Votre véhicule", "Tu vehículo", "Dein Fahrzeug",
                                 "Il tuo veicolo", "O teu veículo"),
    "onboarding.vehicle.subtitle": (
        "Uniquement ce dont le barème de votre pays a réellement besoin.",
        "Solo lo que el baremo de tu país necesita de verdad.",
        "Nur das, was die Pauschale deines Landes wirklich braucht.",
        "Solo ciò che serve davvero alla tabella del tuo paese.",
        "Apenas o que a tabela do teu país precisa mesmo.",
    ),
    "onboarding.skip": ("Plus tard", "Ahora no", "Später", "Più tardi", "Agora não"),
    "onboarding.location.title": ("Autorisez Mileage Pocket à suivre vos trajets",
                                  "Permite que Mileage Pocket registre tus viajes",
                                  "Erlaube Mileage Pocket, deine Fahrten aufzuzeichnen",
                                  "Consenti a Mileage Pocket di registrare i tuoi viaggi",
                                  "Permite que o Mileage Pocket registe as tuas viagens"),
    "onboarding.location.subtitle": (
        "L’accès à la position permet de calculer vos kilomètres même quand votre iPhone est verrouillé.",
        "El acceso a la ubicación permite calcular tus kilómetros aunque el iPhone esté bloqueado.",
        "Mit Standortzugriff werden deine Kilometer auch bei gesperrtem iPhone berechnet.",
        "L’accesso alla posizione permette di calcolare i chilometri anche con l’iPhone bloccato.",
        "O acesso à localização permite calcular os teus quilómetros mesmo com o iPhone bloqueado.",
    ),
    "onboarding.location.detail": (
        "Vos positions restent sur votre iPhone et dans votre iCloud. Elles ne sont jamais vendues, partagées ni transmises à un annonceur.",
        "Tus posiciones se quedan en tu iPhone y en tu iCloud. Nunca se venden, se comparten ni se envían a un anunciante.",
        "Deine Standorte bleiben auf deinem iPhone und in deiner iCloud. Sie werden nie verkauft, geteilt oder an Werbetreibende weitergegeben.",
        "Le tue posizioni restano sul tuo iPhone e nel tuo iCloud. Non vengono mai vendute, condivise né inviate a un inserzionista.",
        "As tuas posições ficam no teu iPhone e no teu iCloud. Nunca são vendidas, partilhadas nem enviadas a anunciantes.",
    ),
    "onboarding.location.allow": ("Autoriser la localisation", "Permitir el acceso a la ubicación",
                                  "Standortzugriff erlauben", "Consenti l’accesso alla posizione",
                                  "Permitir o acesso à localização"),
    "onboarding.notifications.title": ("Gardez le fil de vos trajets", "No pierdas de vista tus viajes",
                                       "Behalte deine Fahrten im Blick", "Tieni d’occhio i tuoi viaggi",
                                       "Fica a par das tuas viagens"),
    "onboarding.notifications.subtitle": (
        "Un rappel si un trajet tourne encore, et un signal quand votre rapport mensuel vaut le coup.",
        "Un aviso si un viaje sigue en curso y otro cuando toca generar el informe mensual.",
        "Eine Erinnerung, wenn eine Fahrt noch läuft, und ein Hinweis, wenn sich der Monatsbericht lohnt.",
        "Un promemoria se un viaggio è ancora in corso e un avviso quando conviene generare il report mensile.",
        "Um lembrete se uma viagem ainda estiver a decorrer e um aviso quando valer a pena gerar o relatório mensal.",
    ),
    "onboarding.notifications.allow": ("Activer les notifications", "Activar las notificaciones",
                                       "Mitteilungen aktivieren", "Attiva le notifiche",
                                       "Ativar as notificações"),

    # --- notifications ----------------------------------------------------
    "notification.trip.running.title": ("Trajet toujours en cours", "Viaje aún en curso",
                                        "Fahrt läuft noch", "Viaggio ancora in corso",
                                        "Viagem ainda a decorrer"),
    "notification.trip.running.body": (
        "Mileage Pocket enregistre depuis trois heures. Arrêtez le trajet si vous êtes arrivé.",
        "Mileage Pocket lleva tres horas grabando. Detén el viaje si ya has llegado.",
        "Mileage Pocket zeichnet seit drei Stunden auf. Beende die Fahrt, wenn du angekommen bist.",
        "Mileage Pocket sta registrando da tre ore. Termina il viaggio se sei arrivato.",
        "O Mileage Pocket está a gravar há três horas. Termina a viagem se já chegaste.",
    ),
    "notification.trip.saved.title": ("Trajet enregistré", "Viaje guardado", "Fahrt gespeichert",
                                      "Viaggio salvato", "Viagem guardada"),
    "notification.trip.saved.body": ("Nouveau trajet enregistré : %@", "Nuevo viaje guardado: %@",
                                     "Neue Fahrt gespeichert: %@", "Nuovo viaggio salvato: %@",
                                     "Nova viagem guardada: %@"),
    "notification.report.title": ("Votre rapport mensuel peut être généré",
                                  "Ya puedes generar tu informe mensual",
                                  "Dein Monatsbericht kann erstellt werden",
                                  "Puoi generare il tuo report mensile",
                                  "Já podes gerar o teu relatório mensal"),
    "notification.report.body": (
        "Les trajets professionnels du mois dernier sont enregistrés. Exportez le PDF tant que c’est frais.",
        "Los viajes profesionales del mes pasado ya están. Exporta el PDF mientras lo tienes fresco.",
        "Die geschäftlichen Fahrten des letzten Monats sind da. Exportiere das PDF, solange es frisch ist.",
        "I viaggi di lavoro del mese scorso ci sono tutti. Esporta il PDF finché è fresco.",
        "As viagens de trabalho do mês passado já estão registadas. Exporta o PDF enquanto está fresco.",
    ),

    # --- misc -------------------------------------------------------------
    "report.unnamed.driver": ("Conducteur", "Conductor", "Fahrer", "Conducente", "Condutor"),
    "widget.start.trip": ("Démarrer un trajet", "Iniciar viaje", "Fahrt starten",
                          "Avvia viaggio", "Iniciar viagem"),
    "widget.month.total": ("Ce mois-ci", "Este mes", "Dieser Monat", "Questo mese", "Este mês"),
}

# Keys where a %lld governs a noun: emit a CLDR plural variation instead of a
# single form. lang -> (one, other). "en" included: it overrides strings_en.json.
PLURALS = {
    "home.business.trips": {
        "en": ("%lld business trip", "%lld business trips"),
        "fr": ("%lld trajet professionnel", "%lld trajets professionnels"),
        "es": ("%lld viaje profesional", "%lld viajes profesionales"),
        "de": ("%lld geschäftliche Fahrt", "%lld geschäftliche Fahrten"),
        "it": ("%lld viaggio di lavoro", "%lld viaggi di lavoro"),
        "pt": ("%lld viagem de trabalho", "%lld viagens de trabalho"),
    },
}

# ---------------------------------------------------------------------------
# French typography: narrow/no-break space before the double punctuation marks.
# Applied programmatically so the table above stays readable.
# ---------------------------------------------------------------------------
NBSP = " "


def french_typography(value):
    value = re.sub(r" +([:;?!»])", NBSP + r"\1", value)
    value = re.sub(r"« +", "«" + NBSP, value)
    return value


POSTPROCESS = {"fr": french_typography}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural_unit(one, other):
    return {
        "variations": {
            "plural": {
                "one": unit(one),
                "other": unit(other),
            }
        }
    }


def build():
    with open(SOURCE, encoding="utf-8") as handle:
        english = json.load(handle)

    all_langs = [SOURCE_LANGUAGE] + LANGUAGES
    strings = {}
    problems = []

    for key, en_value in english.items():
        plural = PLURALS.get(key)
        translated = TRANSLATIONS.get(key)

        if plural is None and translated is None:
            problems.append("missing translation for key: %s" % key)
            continue
        if translated is not None and len(translated) != len(LANGUAGES):
            problems.append("key %s has %d translations, expected %d"
                            % (key, len(translated), len(LANGUAGES)))
            continue

        localizations = {}
        for index, lang in enumerate(all_langs):
            if plural is not None:
                if lang not in plural:
                    problems.append("missing plural for %s / %s" % (key, lang))
                    continue
                one, other = plural[lang]
                post = POSTPROCESS.get(lang, lambda v: v)
                localizations[lang] = plural_unit(post(one), post(other))
            else:
                value = en_value if lang == SOURCE_LANGUAGE else translated[index - 1]
                post = POSTPROCESS.get(lang, lambda v: v)
                localizations[lang] = unit(post(value))

        strings[key] = {
            "extractionState": "manual",
            "localizations": localizations,
        }

    extra = sorted(set(TRANSLATIONS) | set(PLURALS) - set(english))
    extra = [k for k in extra if k not in english]
    for key in extra:
        problems.append("translation for unknown key: %s" % key)

    if problems:
        for problem in problems:
            sys.stderr.write("ERROR: %s\n" % problem)
        return 1

    catalogue = {
        "sourceLanguage": SOURCE_LANGUAGE,
        "strings": dict(sorted(strings.items())),
        "version": "1.0",
    }

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as handle:
        json.dump(catalogue, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")

    print("wrote %s" % OUTPUT)
    print("%d keys x %d languages = %d units"
          % (len(strings), len(all_langs), len(strings) * len(all_langs)))
    return 0


if __name__ == "__main__":
    sys.exit(build())
