"""Public synthetic controls. These never establish accuracy on room recordings."""
CONTROLS = {
 'answered_question': {
  'utterances': [('Sprecher 1','Was hattest du heute in der Schule?'),('Sprecher 2','Deutsch und Mathematik.'),('Sprecher 1','Danke. Komm bitte näher und sag kurz Hallo, damit ich das Mikrofon testen kann.'),('Sprecher 2','Hallo, ich bin jetzt neben dir.')],
  'expected': {'facts':['Deutsch','Mathematik'],'decisions':0,'tasks':0,'openQuestions':0},
 },
 'conditional_payment': {
  'utterances': [('Sprecher 1','Ich weiß nicht, ob Person A das Geld erhalten hat. Das ist bislang nicht belegt.'),('Sprecher 2','Wenn sie den Erhalt bestätigt, ist die Zahlung geklärt. Wenn sie Nein sagt, müssen wir weiter nachforschen.'),('Sprecher 1','Genau. Ich frage Person A morgen danach. Mehr beschließen wir heute nicht.')],
  'expected': {'preserveUnconfirmedPayment':True,'noDefinitiveReceipt':True,'tasks':['Sprecher 1 fragt Person A morgen'],'decisions':0},
 },
 'decision_and_opposition': {
  'utterances': [('Sprecher 1','Vorschlag: Wir bestellen 30 Geräte für insgesamt 2400 Euro.'),('Sprecher 2','Ich bin dagegen. Wir sollten erst 10 Geräte testen.'),('Sprecher 1','Einverstanden. Beschlossen sind nur 10 Testgeräte, maximal 800 Euro. Die restlichen 20 werden nicht bestellt.'),('Sprecher 2','Ich hole bis Freitag ein Angebot dafür ein. Ob wir danach erweitern, bleibt offen.')],
  'expected': {'facts':['10','800','20','Freitag'],'preserveOpposition':True,'decision':'10 Testgeräte maximal 800 Euro','notDecision':'30 Geräte für 2400 Euro','task':'Sprecher 2 Angebot bis Freitag','openQuestion':'Erweiterung nach Test'},
 }
}

def transcript(control):
    return {'schemaVersion':2,'segments':[{'id':f'control-{i+1}','tStart':i*8,'tEnd':i*8+7,'speaker':speaker,'speakerId':speaker,'channel':'mic','text':text,'uncertain':False} for i,(speaker,text) in enumerate(control['utterances'])]}
